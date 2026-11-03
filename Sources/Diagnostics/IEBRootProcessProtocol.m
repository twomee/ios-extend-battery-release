#import "IEBRootProcessProtocol.h"
#import <limits.h>
#import <math.h>
const char *IEBRootProcessServiceName = "com.idonamaan.ieb.process-reader";
static id Fail(NSError **error) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBRootProcessProtocol"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : @"Invalid root process response"}];
    return nil;
}
static BOOL Number(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]);
}
static BOOL Integer(id n, double minimum, double maximum) {
    return Number(n) && [n doubleValue] >= minimum && [n doubleValue] <= maximum &&
           [n doubleValue] == floor([n doubleValue]);
}
BOOL IEBRootProcessCallerAllowed(uid_t uid, NSString *identity, uint32_t flags) {
    // CS_VALID | CS_PLATFORM_BINARY. Check audited kernel signing flags, not client-supplied fields.
    return uid == 0 || (uid == 501 && [identity isEqualToString:@"com.apple.Preferences"] &&
                        (flags & 0x04000001) == 0x04000001);
}
BOOL IEBRootProcessRequestValid(NSDictionary *request) {
    return [request isKindOfClass:NSDictionary.class] && request.count == 2 &&
           Integer(request[@"version"], 1, 1) && [request[@"operation"] isEqual:@"snapshot"];
}
static BOOL Snapshot(NSDictionary *s) {
    if (![s isKindOfClass:NSDictionary.class] || s.count > 17 || ![s[@"rows"] isKindOfClass:NSArray.class] ||
        [s[@"rows"] count] > 8192 ||
        ![@[ @"available", @"partial", @"unavailable" ] containsObject:s[@"status"]] ||
        ![s[@"cpu_scope"] isEqual:@"process_lifetime"] || ![s[@"cpu_unit"] isEqual:@"seconds"] ||
        ![s[@"cpu_source"] isEqual:@"proc_pid_rusage_v2_mach_absolute"] ||
        ![s[@"battery_attribution"] isEqual:@"unavailable"])
        return NO;
    for (NSString *key in @[
             @"enumerated_count", @"unavailable_count", @"permission_denied_count", @"vanished_count",
             @"name_unavailable_count"
         ])
        if (!Integer(s[key], 0, 8192))
            return NO;
    NSUInteger rows = [s[@"rows"] count], enumerated = [s[@"enumerated_count"] unsignedIntegerValue],
               unavailable = [s[@"unavailable_count"] unsignedIntegerValue];
    if (rows + unavailable != enumerated ||
        [s[@"permission_denied_count"] unsignedIntegerValue] > unavailable ||
        [s[@"vanished_count"] unsignedIntegerValue] > unavailable ||
        [s[@"name_unavailable_count"] unsignedIntegerValue] > rows)
        return NO;
    if (rows && (!Integer(s[@"timebase_numerator"], 1, UINT32_MAX) ||
                 !Integer(s[@"timebase_denominator"], 1, UINT32_MAX)))
        return NO;
    NSMutableSet *pids = [NSMutableSet new];
    for (id r in s[@"rows"]) {
        if (![r isKindOfClass:NSDictionary.class] || [r count] != 5 || !Integer(r[@"pid"], 1, INT_MAX) ||
            [pids containsObject:r[@"pid"]] || ![r[@"name"] isKindOfClass:NSString.class] ||
            [r[@"name"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1023 ||
            [r[@"name"] rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound ||
            !Integer(r[@"start_ticks"], 1, (double)UINT64_MAX) || !Number(r[@"cpu_seconds"]) ||
            [r[@"cpu_seconds"] doubleValue] < 0 || [r[@"cpu_seconds"] doubleValue] > 1e12 ||
            !Number(r[@"sampled_at"]) || [r[@"sampled_at"] doubleValue] <= 0 ||
            [r[@"sampled_at"] doubleValue] > 1e12)
            return NO;
        [pids addObject:r[@"pid"]];
    }
    return YES;
}
NSData *IEBEncodeRootProcessSnapshot(NSDictionary *snapshot, NSError **error) {
    if (error)
        *error = nil;
    if (!Snapshot(snapshot))
        return Fail(error);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{
        @"version" : @1,
        @"provider_uid" : @0,
        @"snapshot" : snapshot
    }
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data || data.length > 2097152)
        return Fail(error);
    return data;
}
NSDictionary *IEBDecodeRootProcessSnapshot(NSData *data, NSError **error) {
    if (error)
        *error = nil;
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > 2097152)
        return Fail(error);
    id raw = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListImmutable
                                                        format:NULL
                                                         error:error];
    if (![raw isKindOfClass:NSDictionary.class] || [raw count] != 3 || !Integer(raw[@"version"], 1, 1) ||
        !Integer(raw[@"provider_uid"], 0, 0) || !Snapshot(raw[@"snapshot"]))
        return Fail(error);
    NSMutableDictionary *result = [raw[@"snapshot"] mutableCopy];
    result[@"reader_provider"] = @"root-service";
    result[@"reader_failure"] = @"none";
    return result;
}
