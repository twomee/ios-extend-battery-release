#import "../Sources/Session/IEBPowerObserver.h"
#import "../Sources/Statistics/IEBCaptureSnapshot.h"
#import "../Sources/Statistics/IEBNativeJournal.h"
#import "../producerprobe/IEBActivityCapture.h"
#import "../producerprobe/IEBNativeCapture.h"
#import <sqlite3.h>
#import <stdatomic.h>
#import <unistd.h>
// Only the independent legacy IOPS observer is substituted; journal and collector are real.
@implementation IEBPowerObserver
- (instancetype)initWithState:(IEBSessionState *)state
                      handler:(void (^)(IEBSessionState *, NSError *))handler {
    (void)state;
    (void)handler;
    return [super init];
}
- (IEBSessionState *)state {
    return nil;
}
- (BOOL)start:(NSError **)error {
    (void)error;
    return NO;
}
- (void)stop {
}
@end
@interface ThrowingEntry : NSObject
- (id)objectForKeyedSubscript:(id)key;
@end
@implementation ThrowingEntry
- (id)objectForKeyedSubscript:(id)key {
    (void)key;
    @throw [NSException exceptionWithName:@"Fixture" reason:@"broken native entry" userInfo:nil];
}
@end
#define REQUIRE(...)                                                                                         \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Native capture FAIL %d: %s\n", __LINE__, #__VA_ARGS__);                         \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static atomic_int ticks;
static atomic_int clockReads;
static NSDate *D(double t) { return [NSDate dateWithTimeIntervalSince1970:t]; }
static NSDictionary *Wait(NSString *dir, NSString *key, double expected) {
    for (int i = 0; i < 200; i++) {
        NSDictionary *r = IEBReadNativeJournal(dir, NULL);
        if (r && [r[@"window"][key] doubleValue] == expected)
            return r;
        usleep(10000);
    }
    return nil;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        REQUIRE(argc == 2);
        NSString *scenario = [NSString stringWithUTF8String:argv[1]];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        REQUIRE([NSFileManager.defaultManager createDirectoryAtPath:dir
                                        withIntermediateDirectories:NO
                                                         attributes:@{
                                                             NSFilePosixPermissions : @0700
                                                         }
                                                              error:NULL]);
        REQUIRE(setenv("IEB_NATIVE_TEST_DIRECTORY", dir.fileSystemRepresentation, 1) == 0);
        atomic_store(&ticks, 100);
        atomic_store(&clockReads, 0);
        IEBStartNativeCapture(^{
            atomic_fetch_add(&clockReads, 1);
            return atomic_load(&ticks) < 0 ? nil : D(atomic_load(&ticks));
        });
        REQUIRE(Wait(dir, @"last_native_time", 100));
        // The initial journal exists before startup marks the collector ready.
        // The first timer clock read occurs after readiness; wait for that boundary
        // before submitting fixture callbacks, including on slow CI storage.
        for (int i = 0; i < 200 && atomic_load(&clockReads) < 2; i++)
            usleep(10000);
        REQUIRE(atomic_load(&clockReads) >= 2);
        IEBObserveNativePower(@1, D(101));
        IEBObserveNativePower(@0, D(110));
        if ([scenario isEqual:@"bridge"]) {
            // Diagnostic collector has never started: its gate must not drop native data.
            IEBObserveActivityAggregate(
                @{@"BundleID" : @"app.private",
                  @"ScreenOnTime" : @10},
                D(110), D(120));
        } else {
            IEBObserveNativeActivity(@{@"BundleID" : @"app.private", @"ScreenOnTime" : @10}, D(110), D(120));
        }
        atomic_store(&ticks, 130);
        REQUIRE(Wait(dir, @"effective_end", 130));
        NSDictionary *r = IEBReadNativeJournal(dir, NULL);
        REQUIRE([r[@"apps"][@"app.private"][@"ScreenOnTime"] doubleValue] == 10);
        atomic_store(&ticks, 150);
        IEBObserveNativePower(@1, D(140));
        REQUIRE(Wait(dir, @"end", 140));
        atomic_store(&ticks, 150);
        IEBObserveNativePower(@0, D(141));
        REQUIRE(Wait(dir, @"start", 141));
        r = IEBReadNativeJournal(dir, NULL);
        REQUIRE([r[@"app_count"] integerValue] == 0);
        if ([scenario isEqual:@"storage"]) {
            sqlite3 *db = NULL;
            NSString *path = [dir stringByAppendingPathComponent:@"native-journal.sqlite"];
            REQUIRE(sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK);
            REQUIRE(
                sqlite3_exec(
                    db,
                    "CREATE TRIGGER deny_meta BEFORE UPDATE ON meta BEGIN SELECT RAISE(FAIL,'fixture'); END",
                    NULL, NULL, NULL) == SQLITE_OK);
            REQUIRE(sqlite3_close(db) == SQLITE_OK);
            IEBObserveNativePower(@1, D(151));
        } else if ([scenario isEqual:@"gap-rejected"]) {
            IEBObserveNativePower(@0, D(170));
            IEBObserveNativePower(@2, D(171));
        } else if ([scenario isEqual:@"throwing"]) {
            IEBObserveActivityAggregate([ThrowingEntry new], D(141), D(145));
        } else if ([scenario isEqual:@"metadata"]) {
            // Validation must happen before copying arbitrary malformed metadata.
            IEBObserveNativeActivity(@{@"BundleID" : [NSObject new], @"ScreenOnTime" : @1}, D(141), D(142));
        } else if ([scenario isEqual:@"clock"]) {
            atomic_store(&ticks, -1);
        } else {
            IEBObserveNativePower(@2, D(151));
        }
        for (int i = 0; i < 200; i++) {
            NSDictionary *status = [NSDictionary
                dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"native-status.plist"]];
            if ([status[@"failed"] boolValue]) {
                REQUIRE(![status.description containsString:@"app.private"]);
                if ([scenario isEqual:@"clock"])
                    REQUIRE([status[@"failure_reason"] isEqual:@"native-clock"]);
                NSError *snapshotError = nil;
                NSDictionary *partial = IEBReadCaptureSnapshot(dir, &snapshotError);
                // The 20ms test writer may replace/chmod status between reads.
                // A fail-closed unavailable read is allowed; a healthy result is not.
                if (!partial) {
                    REQUIRE(snapshotError);
                    usleep(10000);
                    continue;
                }
                REQUIRE(![partial[@"source_healthy"] boolValue]);
                REQUIRE([partial[@"source_failed"] boolValue]);
                REQUIRE(![partial[@"window"][@"power_complete"] boolValue]);
                IEBStopNativeCaptureForTesting();
                REQUIRE([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
                puts("PASS native power/activity capture, cycle reset and explicit source failure");
                return 0;
            }
            usleep(10000);
        }
        REQUIRE(NO);
    }
}
