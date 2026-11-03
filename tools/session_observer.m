// Bounded standalone diagnostic. Does not install a launch daemon.
#import "../Sources/Session/IEBPowerObserver.h"
#import "../Sources/Session/IEBSessionStore.h"
#import <sys/stat.h>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "Usage: session-observer PRIVATE_DIRECTORY SECONDS(1..300)\n");
            return 64;
        }
        char *end = NULL;
        long duration = strtol(argv[2], &end, 10);
        if (!*argv[2] || *end || duration < 1 || duration > 300)
            return 64;
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        if (!directory.isAbsolutePath)
            return 64;
        if (mkdir(directory.fileSystemRepresentation, 0700) != 0 && errno != EEXIST)
            return 74;
        NSError *error = nil;
        IEBSessionState *restored = IEBLoadSession(directory, &error);
        if (error) {
            fprintf(stderr, "Snapshot load failed: %s\n", error.localizedDescription.UTF8String);
            return 74;
        }
        __block int result = 22;
        __block NSUInteger observations = 0;
        IEBPowerObserver *observer = [[IEBPowerObserver alloc]
            initWithState:restored
                  handler:^(IEBSessionState *state, NSError *failure) {
                      NSError *saveError = nil;
                      if (failure || !IEBSaveSession(state, directory, &saveError)) {
                          fprintf(stderr, "Observation/store failed: %s\n",
                                  (failure ?: saveError).localizedDescription.UTF8String);
                          result = 74;
                          CFRunLoopStop(CFRunLoopGetCurrent());
                          return;
                      }
                      observations++;
                      NSDictionary *safe = @{
                          @"observation_count" : @(observations),
                          @"external_power" : @(state.externalPower),
                          @"has_session" : @(state.start != nil),
                          @"session_complete" : @(state.complete),
                          @"frozen" : @(state.end != nil),
                          @"feature_ready" : @NO
                      };
                      NSData *json = [NSJSONSerialization dataWithJSONObject:safe
                                                                     options:NSJSONWritingSortedKeys
                                                                       error:&saveError];
                      if (!json) {
                          result = 74;
                          CFRunLoopStop(CFRunLoopGetCurrent());
                          return;
                      }
                      puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
                      fflush(stdout);
                  }];
        if (![observer start:&error]) {
            fprintf(stderr, "Observer start failed: %s\n", error.localizedDescription.UTF8String);
            return 23;
        }
        if (result == 22)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, (CFTimeInterval)duration, false);
        [observer stop];
        IEBSessionState *loaded = IEBLoadSession(directory, &error);
        if (!loaded || error)
            return 74;
        return result;
    }
}
