#import "../Sources/Statistics/IEBCaptureSnapshot.h"
#import "../Sources/Statistics/IEBNativeJournal.h"
#import <sys/stat.h>
#import <unistd.h>
#define REQUIRE(...)                                                                                         \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Snapshot FAIL %d: %s\n", __LINE__, #__VA_ARGS__);                               \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static BOOL Save(NSDictionary *status, NSString *path) {
    return [status writeToFile:path atomically:YES] && chmod(path.fileSystemRepresentation, 0600) == 0;
}
int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        REQUIRE([NSFileManager.defaultManager createDirectoryAtPath:dir
                                        withIntermediateDirectories:NO
                                                         attributes:@{
                                                             NSFilePosixPermissions : @0700
                                                         }
                                                              error:NULL]);
        NSError *error = nil;
        IEBNativeJournal *j = [[IEBNativeJournal alloc] initWithDirectory:dir
                                                                    epoch:@"fixture"
                                                               nativeTime:100
                                                                    error:&error];
        REQUIRE(j && [j recordPower:1 nativeTime:100 error:&error] &&
                [j recordPower:0 nativeTime:110 error:&error] && [j checkpointAtNativeTime:130 error:&error]);
        NSString *path = [dir stringByAppendingPathComponent:@"native-status.plist"];
        NSMutableDictionary *status = [@{
            @"version" : @1,
            @"failure_reason" : @"none",
            @"writer_epoch" : @"fixture",
            @"writer_pid" : @(getpid()),
            @"observed_wall_time" : @(NSDate.date.timeIntervalSince1970),
            @"failed" : @NO,
            @"error_count" : @0,
            @"feature_ready" : @NO
        } mutableCopy];
        REQUIRE(Save(status, path));
        NSDictionary *r = IEBReadCaptureSnapshot(dir, &error);
        REQUIRE(r && !error && [r[@"source_healthy"] boolValue] && [r[@"writer_current"] boolValue]);
        status[@"failed"] = @YES;
        REQUIRE(Save(status, path));
        r = IEBReadCaptureSnapshot(dir, &error);
        REQUIRE(r && [r[@"source_failed"] boolValue] && ![r[@"source_healthy"] boolValue] &&
                ![r[@"window"][@"power_complete"] boolValue]);
        REQUIRE([r[@"window"][@"effective_end"] doubleValue] == 130);
        status[@"failed"] = @NO;
        status[@"writer_epoch"] = @"other";
        REQUIRE(Save(status, path));
        r = IEBReadCaptureSnapshot(dir, &error);
        REQUIRE(r && ![r[@"writer_current"] boolValue] && [r[@"source_failed"] boolValue]);
        status[@"writer_epoch"] = @"fixture";
        status[@"observed_wall_time"] = @1;
        REQUIRE(Save(status, path));
        r = IEBReadCaptureSnapshot(dir, &error);
        REQUIRE(r && ![r[@"source_healthy"] boolValue]);
        status[@"writer_pid"] = @YES;
        REQUIRE(Save(status, path));
        REQUIRE(!IEBReadCaptureSnapshot(dir, &error) && error);
        REQUIRE(unlink(path.fileSystemRepresentation) == 0 &&
                symlink("/dev/null", path.fileSystemRepresentation) == 0);
        REQUIRE(!IEBReadCaptureSnapshot(dir, &error) && error);
        j = nil;
        REQUIRE([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
        puts("PASS native status identity, failure, stale metadata and private file validation");
        return 0;
    }
}
