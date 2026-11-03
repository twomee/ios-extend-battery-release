#import "IEBActivityCapture.h"
#import "../Sources/Session/IEBPowerObserver.h"
#import "../Sources/Session/IEBSessionStore.h"
#import "../Sources/Statistics/IEBActivityEvidence.h"
#import "IEBNativeCapture.h"
#import <math.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <unistd.h>

static dispatch_queue_t queue;
static IEBPowerObserver *observer;
static dispatch_source_t evidenceTimer;
static NSMutableDictionary *totals;
static unsigned long long callbacks, appIntervals, invalid, exceeding, storeErrors;
static double first, last;
static BOOL installed;
static atomic_bool observerFailed, ready;
static atomic_uint pending, dropped;
static NSString *Directory(void) {
#if IEB_ACTIVITY_CAPTURE_TESTING
    return [NSString stringWithUTF8String:getenv("IEB_ACTIVITY_TEST_DIRECTORY")];
#else
    return @"/var/mobile/Library/IEBNativeCapture";
#endif
}
static void Flush(void) {
    NSDictionary *summary = @{
        @"schema_version" : @1,
        @"writer_pid" : @(getpid()),
        @"native_hook_installed" : @(installed),
        @"observer_failed" : @(atomic_load(&observerFailed)),
        @"interval_count" : @(callbacks),
        @"app_interval_count" : @(appIntervals),
        @"invalid_interval_count" : @(invalid),
        @"value_exceeds_span_count" : @(exceeding),
        @"dropped_callback_count" : @(atomic_load(&dropped)),
        @"store_error_count" : @(storeErrors),
        @"earliest_native_start" : @(first),
        @"latest_native_end" : @(last),
        @"observed_wall_time" : @(NSDate.date.timeIntervalSince1970),
        @"metric_totals" : [totals copy],
        @"feature_ready" : @NO
    };
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:summary
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    NSString *path = [Directory() stringByAppendingPathComponent:@"activity-evidence.plist"];
    BOOL ok = data && [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (ok)
        ok = [NSFileManager.defaultManager setAttributes:@{
            NSFilePosixPermissions : @0600
        }
                                            ofItemAtPath:path
                                                   error:&error];
    if (!ok) {
        storeErrors++;
        if (storeErrors == 1)
            NSLog(@"IEB activity diagnostic could not save aggregate evidence");
    }
}
static void StartEvidenceTimer(void) {
    evidenceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
#if IEB_ACTIVITY_CAPTURE_TESTING
    uint64_t interval = 20 * NSEC_PER_MSEC;
#else
    uint64_t interval = 30 * NSEC_PER_SEC;
#endif
    dispatch_source_set_timer(evidenceTimer, DISPATCH_TIME_NOW, interval, interval / 10);
    dispatch_source_set_event_handler(evidenceTimer, ^{
        Flush();
    });
    dispatch_resume(evidenceTimer);
    atomic_store(&ready, true);
}
void IEBStartActivityCapture(BOOL hookInstalled) {
    if (queue)
        return;
    installed = hookInstalled;
    totals = [NSMutableDictionary new];
    queue = dispatch_queue_create("com.idonamaan.ieb.activity-evidence", DISPATCH_QUEUE_SERIAL);
    // The persistent target runs as mobile. Root/on-demand helperd never starts this collector.
    NSError *error = nil;
    if (mkdir(Directory().fileSystemRepresentation, 0700) != 0 && errno != EEXIST) {
        observerFailed = YES;
        NSLog(@"IEB activity diagnostic directory unavailable");
        return;
    }
    if (!IEBValidateSessionDirectory(Directory(), &error)) {
        observerFailed = YES;
        NSLog(@"IEB activity diagnostic directory is not private");
        return;
    }
    IEBSessionState *restored = IEBLoadSession(Directory(), &error);
    if (error) {
        observerFailed = YES;
        storeErrors++;
        StartEvidenceTimer();
        return;
    }
    observer =
        [[IEBPowerObserver alloc] initWithState:restored
                                        handler:^(IEBSessionState *state, NSError *failure) {
                                            dispatch_async(queue, ^{
                                                NSError *saveError = nil;
                                                if (failure)
                                                    observerFailed = YES;
                                                else if (!IEBSaveSession(state, Directory(), &saveError)) {
                                                    observerFailed = YES;
                                                    storeErrors++;
                                                }
                                                Flush();
                                            });
                                        }];
    if (![observer start:&error]) {
        observerFailed = YES;
        dispatch_async(queue, ^{
            Flush();
        });
    }
    StartEvidenceTimer();
}
void IEBObserveActivityAggregate(id entry, NSDate *start, NSDate *end) {
    IEBObserveNativeActivityEntry(entry, start, end);
    if (!atomic_load(&ready))
        return;
    if (atomic_fetch_add(&pending, 1) >= 128) {
        atomic_fetch_sub(&pending, 1);
        atomic_fetch_add(&dropped, 1);
        return;
    }
    NSDictionary *evidence = nil;
    NSError *error = nil;
    @try {
        // PLEntry has keyed subscripting. Copy only allowlisted scalar duration fields.
        NSMutableDictionary *allowed = [NSMutableDictionary new];
        for (NSString *key in IEBActivityMetricKeys()) {
            id value = [entry objectForKeyedSubscript:key];
            if (value)
                allowed[key] = value;
        }
        id bundle = [entry objectForKeyedSubscript:@"BundleID"];
        if (bundle)
            allowed[@"BundleID"] = bundle;
        evidence = IEBActivityEvidence(allowed, start, end, &error);
    } @catch (NSException *exception) {
        (void)exception;
        error = [NSError errorWithDomain:@"IEBActivityCapture" code:1 userInfo:nil];
    }
    if (!evidence && !error) {
        atomic_fetch_sub(&pending, 1);
        return;
    }
    // Diagnostic summary excludes app identities; the separate private journal retains them.
    dispatch_async(queue, ^{
        if (!evidence)
            invalid++;
        else {
            BOOL finite = YES;
            for (NSString *key in evidence[@"metrics"]) {
                double value = [totals[key] doubleValue] + [evidence[@"metrics"][key] doubleValue];
                if (!isfinite(value))
                    finite = NO;
            }
            if (!finite)
                invalid++;
            else {
                callbacks++;
                appIntervals += [evidence[@"has_app"] boolValue] ? 1 : 0;
                exceeding += [evidence[@"value_exceeds_span"] boolValue] ? 1 : 0;
                double a = [evidence[@"start"] doubleValue], b = [evidence[@"end"] doubleValue];
                first = first ? MIN(first, a) : a;
                last = MAX(last, b);
                for (NSString *key in evidence[@"metrics"])
                    totals[key] = @([totals[key] doubleValue] + [evidence[@"metrics"][key] doubleValue]);
            }
        }
        atomic_fetch_sub(&pending, 1);
    });
}

#if IEB_ACTIVITY_CAPTURE_TESTING
void IEBStopActivityCaptureForTesting(void) {
    atomic_store(&ready, false);
    if (queue)
        dispatch_sync(queue, ^{
            if (evidenceTimer)
                dispatch_source_cancel(evidenceTimer);
            evidenceTimer = nil;
        });
}
#endif
