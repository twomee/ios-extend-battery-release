#import "IEBNativeCapture.h"
#import "../Sources/Session/IEBSessionStore.h"
#import "../Sources/Statistics/IEBActivityEvidence.h"
#import "../Sources/Statistics/IEBNativeJournal.h"
#import <math.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <unistd.h>

static dispatch_queue_t queue;
static dispatch_source_t timer;
static IEBNativeJournal *journal;
static NSDate * (^nativeClock)(void);
static atomic_bool ready, lost;
static atomic_uint pending;
static BOOL failed;
static NSUInteger errors;
static NSString *writerEpoch, *failureReason;
static NSString *Directory(void) {
#if IEB_NATIVE_CAPTURE_TESTING
    return [NSString stringWithUTF8String:getenv("IEB_NATIVE_TEST_DIRECTORY")];
#else
    return @"/var/mobile/Library/IEBNativeCapture";
#endif
}
static double Clock(void) {
    @try {
        id date = nativeClock ? nativeClock() : nil;
        return [date isKindOfClass:NSDate.class] ? [date timeIntervalSince1970] : NAN;
    } @catch (NSException *exception) {
        (void)exception;
        return NAN;
    }
}
static void Failure(NSString *reason) {
    if (!failed) {
        failed = YES;
        failureReason = reason;
        atomic_store(&ready, false);
        double t = Clock();
        NSError *error = nil;
        if (journal && ![journal markSourceFailed:&error])
            errors++;
        if (journal && (![journal recordGapAtNativeTime:t error:&error]))
            errors++;
        NSLog(@"IEB native source interrupted; statistics are incomplete");
    }
    errors++;
}
static void Status(void) {
    NSDictionary *status = @{
        @"version" : @1,
        @"failure_reason" : failureReason ?: @"none",
        @"writer_epoch" : writerEpoch ?: @"unavailable",
        @"writer_pid" : @(getpid()),
        @"observed_wall_time" : @(NSDate.date.timeIntervalSince1970),
        @"failed" : @(failed),
        @"error_count" : @(errors),
        @"feature_ready" : @NO
    };
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:status
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    NSString *path = [Directory() stringByAppendingPathComponent:@"native-status.plist"];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error] ||
        ![NSFileManager.defaultManager setAttributes:@{
            NSFilePosixPermissions : @0600
        }
                                        ofItemAtPath:path
                                               error:&error]) {
        Failure(@"status-store");
    }
}
static BOOL Reserve(void) {
    if (!atomic_load(&ready))
        return NO;
    if (atomic_fetch_add(&pending, 1) >= 128) {
        atomic_fetch_sub(&pending, 1);
        atomic_store(&lost, true);
        return NO;
    }
    return YES;
}
static BOOL Check(void) {
    if (atomic_exchange(&lost, false))
        Failure(@"queue-overflow");
    return !failed;
}
void IEBStartNativeCapture(NSDate * (^clock)(void)) {
    if (queue)
        return;
    nativeClock = [clock copy];
    queue = dispatch_queue_create("com.idonamaan.ieb.native-journal", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        NSError *error = nil;
        if ((mkdir(Directory().fileSystemRepresentation, 0700) != 0 && errno != EEXIST) ||
            !IEBValidateSessionDirectory(Directory(), &error)) {
            Failure(@"private-directory");
            return;
        }
        writerEpoch = NSUUID.UUID.UUIDString;
        double initialTime = Clock();
        journal = [[IEBNativeJournal alloc] initWithDirectory:Directory()
                                                        epoch:writerEpoch
                                                   nativeTime:initialTime
                                                        error:&error];
        if (!journal)
            Failure(isfinite(initialTime) ? @"journal-init" : @"native-clock");
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
#if IEB_NATIVE_CAPTURE_TESTING
        uint64_t interval = 20 * NSEC_PER_MSEC;
#else
        uint64_t interval = 30 * NSEC_PER_SEC;
#endif
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, interval, interval / 10);
        dispatch_source_set_event_handler(timer, ^{
            if (Check()) {
                NSError *checkpointError = nil;
                double t = Clock();
                if (![journal checkpointAtNativeTime:t error:&checkpointError])
                    Failure(isfinite(t) ? @"journal-checkpoint" : @"native-clock");
            }
            Status();
        });
        Status();
        atomic_store(&ready, !failed);
        dispatch_resume(timer);
    });
}
void IEBObserveNativePower(id connected, NSDate *date) {
    if (!Reserve())
        return;
    BOOL valid = [connected isKindOfClass:NSNumber.class] &&
                 ([connected doubleValue] == 0 || [connected doubleValue] == 1) &&
                 [date isKindOfClass:NSDate.class] && isfinite(date.timeIntervalSince1970) &&
                 date.timeIntervalSince1970 > 0;
    NSInteger value = valid ? [connected integerValue] : -1;
    double t = valid ? date.timeIntervalSince1970 : NAN;
    dispatch_async(queue, ^{
        NSError *error = nil;
        if (Check() && (!valid || ![journal recordPower:value nativeTime:t error:&error]))
            Failure(valid ? @"journal-write" : @"native-power");
        Status();
        atomic_fetch_sub(&pending, 1);
    });
}
static void InvalidRecord(void) {
    dispatch_async(queue, ^{
        Failure(@"native-activity");
        Status();
        atomic_fetch_sub(&pending, 1);
    });
}
void IEBObserveNativeActivity(NSDictionary *entry, NSDate *start, NSDate *end) {
    if (!Reserve())
        return;
    @try {
        NSError *error = nil;
        NSDictionary *evidence = IEBActivityEvidence(entry, start, end, &error);
        if (!evidence) {
            if (error)
                InvalidRecord();
            else
                atomic_fetch_sub(&pending, 1);
            return;
        }
        // Copy metadata only after validation; every reservation is released on errors.
        NSMutableDictionary *record = [evidence[@"metrics"] mutableCopy];
        if (entry[@"BundleID"])
            record[@"BundleID"] = [entry[@"BundleID"] copy];
        NSDictionary *copy = [record copy];
        NSDate *a = [start copy], *b = [end copy];
        dispatch_async(queue, ^{
            NSError *writeError = nil;
            if (Check() && ![journal recordActivity:copy start:a end:b error:&writeError])
                Failure(@"journal-write");
            atomic_fetch_sub(&pending, 1);
        });
    } @catch (NSException *exception) {
        (void)exception;
        InvalidRecord();
    }
}
void IEBObserveNativeActivityEntry(id entry, NSDate *start, NSDate *end) {
    if (!atomic_load(&ready))
        return;
    @try {
        NSMutableDictionary *allowed = [NSMutableDictionary new];
        for (NSString *key in IEBActivityMetricKeys()) {
            id value = [entry objectForKeyedSubscript:key];
            if (value)
                allowed[key] = value;
        }
        id bundle = [entry objectForKeyedSubscript:@"BundleID"];
        if (bundle)
            allowed[@"BundleID"] = bundle;
        IEBObserveNativeActivity(allowed, start, end);
    } @catch (NSException *exception) {
        (void)exception;
        if (Reserve())
            InvalidRecord();
    }
}

#if IEB_NATIVE_CAPTURE_TESTING
void IEBStopNativeCaptureForTesting(void) {
    atomic_store(&ready, false);
    if (queue)
        dispatch_sync(queue, ^{
            if (timer)
                dispatch_source_cancel(timer);
            timer = nil;
            journal = nil;
        });
}
#endif
