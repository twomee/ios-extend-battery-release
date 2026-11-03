#import "IEBProcessSnapshot.h"
#import <dlfcn.h>
#import <errno.h>
#import <limits.h>
#import <mach/mach_time.h>
#import <math.h>
#import <sys/resource.h>

// Signatures match Apple's libsyscall/wrappers/libproc/libproc.h. iPhone SDKs omit that header.
typedef int (*IEBListPIDs)(void *, int);
typedef int (*IEBProcessName)(int, void *, uint32_t);
typedef int (*IEBProcessRusage)(int, int, rusage_info_t *);

double IEBProcessTicksToSeconds(uint64_t ticks, uint32_t numerator, uint32_t denominator) {
    if (!numerator || !denominator)
        return NAN;
    return (double)((long double)ticks * numerator / denominator / 1.0e9L);
}

static BOOL IEBFiniteNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}

NSDictionary *IEBProcessCPUDelta(NSDictionary *before, NSDictionary *after) {
    if (![before isKindOfClass:NSDictionary.class] || ![after isKindOfClass:NSDictionary.class])
        return nil;
    for (NSString *key in @[ @"pid", @"start_ticks", @"cpu_seconds", @"sampled_at" ]) {
        if (!IEBFiniteNumber(before[key]) || !IEBFiniteNumber(after[key]))
            return nil;
    }
    double pid = [before[@"pid"] doubleValue], start = [before[@"start_ticks"] doubleValue];
    if (pid != floor(pid) || pid > INT_MAX || start <= 0 || start != floor(start))
        return nil;
    if ([before[@"pid"] intValue] <= 0 || ![before[@"pid"] isEqual:after[@"pid"]] ||
        [before[@"start_ticks"] unsignedLongLongValue] == 0 ||
        ![before[@"start_ticks"] isEqual:after[@"start_ticks"]])
        return nil;
    double oldCPU = [before[@"cpu_seconds"] doubleValue], newCPU = [after[@"cpu_seconds"] doubleValue];
    double elapsed = [after[@"sampled_at"] doubleValue] - [before[@"sampled_at"] doubleValue];
    if (oldCPU < 0 || newCPU < oldCPU || elapsed <= 0 || !isfinite(elapsed))
        return nil;
    double cpu = newCPU - oldCPU, percent = cpu / elapsed * 100;
    if (!isfinite(cpu) || !isfinite(percent))
        return nil;
    return @{@"cpu_seconds" : @(cpu), @"window_seconds" : @(elapsed), @"cpu_percent" : @(percent)};
}

NSDictionary *IEBReadProcessSnapshot(void) {
    NSMutableDictionary *result = [@{
        @"rows" : @[],
        @"status" : @"unavailable",
        @"cpu_scope" : @"process_lifetime",
        @"cpu_unit" : @"seconds",
        @"cpu_source" : @"proc_pid_rusage_v2_mach_absolute",
        @"battery_attribution" : @"unavailable",
        @"enumerated_count" : @0,
        @"unavailable_count" : @0,
        @"permission_denied_count" : @0,
        @"vanished_count" : @0,
        @"name_unavailable_count" : @0
    } mutableCopy];
    // dlopen is read-only. Close our reference after all calls; function pointers never escape.
    void *library = dlopen("/usr/lib/libproc.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!library) {
        result[@"reason"] = @"libproc_unavailable";
        return result;
    }
    IEBListPIDs list = (IEBListPIDs)dlsym(library, "proc_listallpids");
    IEBProcessName name = (IEBProcessName)dlsym(library, "proc_name");
    IEBProcessRusage usage = (IEBProcessRusage)dlsym(library, "proc_pid_rusage");
    mach_timebase_info_data_t timebase = {0};
    if (!list || !name || !usage || mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.numer ||
        !timebase.denom) {
        result[@"reason"] = @"api_or_clock_unavailable";
        dlclose(library);
        return result;
    }
    result[@"timebase_numerator"] = @(timebase.numer);
    result[@"timebase_denominator"] = @(timebase.denom);
    int estimate = list(NULL, 0);
    // Bound allocation even if an unexpected API result is returned.
    if (estimate <= 0 || estimate > 1024 * 1024) {
        result[@"reason"] = @"enumeration_unavailable";
        dlclose(library);
        return result;
    }
    NSUInteger capacity = (NSUInteger)estimate + 256;
    NSMutableData *buffer = [NSMutableData dataWithLength:capacity * sizeof(int)];
    int count = list(buffer.mutableBytes, (int)buffer.length);
    if (count <= 0 || count > (int)capacity) {
        result[@"reason"] = @"enumeration_unavailable";
        dlclose(library);
        return result;
    }
    BOOL truncated = count == (int)capacity;
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger unavailable = 0, denied = 0, vanished = 0, unnamed = 0, enumerated = 0;
    int *pids = buffer.mutableBytes;
    for (int index = 0; index < count; index++) {
        int pid = pids[index];
        if (pid <= 0)
            continue;
        enumerated++;
        struct rusage_info_v2 info = {0}, verified = {0};
        errno = 0;
        if (usage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&info) != 0) {
            int failure = errno;
            unavailable++;
            denied += failure == EPERM || failure == EACCES;
            vanished += failure == ESRCH;
            continue;
        }
        char processName[1024] = {0};
        int nameLength = name(pid, processName, sizeof(processName));
        // Reading the name separately can race with PID reuse; require the same process instance afterward.
        errno = 0;
        if (usage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&verified) != 0) {
            int failure = errno;
            unavailable++;
            denied += failure == EPERM || failure == EACCES;
            vanished += failure == ESRCH;
            continue;
        }
        if (!info.ri_proc_start_abstime || info.ri_proc_start_abstime != verified.ri_proc_start_abstime) {
            unavailable++;
            vanished++;
            continue;
        }
        double sampled = IEBProcessTicksToSeconds(mach_absolute_time(), timebase.numer, timebase.denom);
        // XNU fill_task_rusage copies task_power_info's Mach absolute counters, not nanoseconds.
        double cpu = IEBProcessTicksToSeconds(verified.ri_user_time, timebase.numer, timebase.denom) +
                     IEBProcessTicksToSeconds(verified.ri_system_time, timebase.numer, timebase.denom);
        NSString *label = nameLength > 0 ? [NSString stringWithUTF8String:processName] : nil;
        if (!label.length)
            unnamed++;
        [rows addObject:@{
            @"pid" : @(pid),
            @"name" : label ?: @"",
            @"start_ticks" : @(verified.ri_proc_start_abstime),
            @"cpu_seconds" : @(cpu),
            @"sampled_at" : @(sampled)
        }];
    }
    dlclose(library);
    result[@"rows"] = rows;
    result[@"enumerated_count"] = @(enumerated);
    result[@"unavailable_count"] = @(unavailable);
    result[@"permission_denied_count"] = @(denied);
    result[@"vanished_count"] = @(vanished);
    result[@"name_unavailable_count"] = @(unnamed);
    result[@"enumeration_truncated"] = @(truncated);
    result[@"status"] =
        !rows.count ? @"unavailable" : ((unavailable || unnamed || truncated) ? @"partial" : @"available");
    return result;
}
