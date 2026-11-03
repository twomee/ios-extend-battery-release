#import "../Sources/Statistics/IEBCaptureSnapshot.h"
#import <signal.h>
int main(int argc, const char *argv[]) {
    (void)argv;
    @autoreleasepool {
        if (argc != 1)
            return 64;
        NSError *error = nil;
        NSDictionary *snapshot = IEBReadCaptureSnapshot(@"/var/mobile/Library/IEBNativeCapture", &error);
        if (!snapshot || error) {
            fprintf(stderr, "Native journal unavailable or invalid\n");
            return 20;
        }
        // Never serialize the per-app dictionary, epoch identifiers or raw source records.
        NSMutableDictionary *safe = [NSMutableDictionary new];
        for (NSString *key in @[
                 @"available", @"source_failed", @"app_count", @"global_metrics",
                 @"overlapping_interval_count", @"boundary_interval_count", @"observed_wall_time",
                 @"writer_pid"
             ])
            if (snapshot[key])
                safe[key] = snapshot[key];
        NSMutableDictionary *window = [NSMutableDictionary new];
        for (NSString *key in
             @[ @"power", @"power_complete", @"start", @"end", @"effective_end", @"last_native_time" ])
            if (snapshot[@"window"][key])
                window[key] = snapshot[@"window"][key];
        safe[@"window"] = window;
        safe[@"writer_current"] = snapshot[@"writer_current"];
        safe[@"source_healthy"] = snapshot[@"source_healthy"];
        safe[@"failure_reason"] = snapshot[@"failure_reason"];
        safe[@"source_coverage_verified"] = @NO;
        safe[@"feature_ready"] = @NO;
        NSData *json =
            [NSJSONSerialization dataWithJSONObject:safe
                                            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                              error:&error];
        if (!json)
            return 74;
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 22;
    }
}
