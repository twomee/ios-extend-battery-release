#import "../Sources/Session/IEBPowerObserver.h"
#import "../producerprobe/IEBActivityCapture.h"
#import <unistd.h>
static void (^callback)(IEBSessionState *, NSError *);
static BOOL startupFails;
@implementation IEBPowerObserver
- (instancetype)initWithState:(IEBSessionState *)state
                      handler:(void (^)(IEBSessionState *, NSError *))handler {
    (void)state;
    self = [super init];
    if (self)
        callback = [handler copy];
    return self;
}
- (IEBSessionState *)state {
    return nil;
}
- (BOOL)start:(NSError **)error {
    if (startupFails && error)
        *error = [NSError errorWithDomain:@"TestObserver" code:1 userInfo:nil];
    return !startupFails;
}
- (void)stop {
}
@end
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Capture FAIL %d: %s\n", __LINE__, #c);                                          \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDictionary *Wait(NSString *path, NSUInteger count) {
    for (int i = 0; i < 100; i++) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
        if (d && [d[@"interval_count"] unsignedIntegerValue] == count)
            return d;
        usleep(10000);
    }
    return nil;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        REQUIRE(argc == 2);
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        REQUIRE([NSFileManager.defaultManager createDirectoryAtPath:dir
                                        withIntermediateDirectories:NO
                                                         attributes:@{
                                                             NSFilePosixPermissions : @0700
                                                         }
                                                              error:NULL]);
        REQUIRE(setenv("IEB_ACTIVITY_TEST_DIRECTORY", dir.fileSystemRepresentation, 1) == 0);
        NSString *path = [dir stringByAppendingPathComponent:@"activity-evidence.plist"];
        BOOL corrupt = strcmp(argv[1], "corrupt") == 0;
        startupFails = strcmp(argv[1], "start-failure") == 0;
        if (corrupt) {
            REQUIRE([@"broken" writeToFile:[dir stringByAppendingPathComponent:@"session.plist"]
                                atomically:NO
                                  encoding:NSUTF8StringEncoding
                                     error:NULL]);
            REQUIRE(([@{@"interval_count" : @99, @"observer_failed" : @NO} writeToFile:path atomically:YES]));
        }
        IEBStartActivityCapture(YES);
        NSDictionary *initial = Wait(path, 0);
        REQUIRE(initial);
        if (!startupFails && !corrupt) {
            REQUIRE(callback);
            callback(nil, [NSError errorWithDomain:@"TestObserver" code:2 userInfo:nil]);
        }
        IEBObserveActivityAggregate(
            @{@"BundleID" : @"app.private",
              @"ScreenOnTime" : @1},
            [NSDate dateWithTimeIntervalSince1970:100], [NSDate dateWithTimeIntervalSince1970:101]);
        NSDictionary *later = Wait(path, 1);
        REQUIRE(later && [later[@"observer_failed"] boolValue]);
        REQUIRE(![later.description containsString:@"app.private"]);
        IEBStopActivityCaptureForTesting();
        REQUIRE([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
        puts("PASS callback evidence survives observer failure and replaces stale startup evidence");
        return 0;
    }
}
