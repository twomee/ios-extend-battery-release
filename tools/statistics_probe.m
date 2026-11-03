#import "../Sources/Statistics/IEBStatisticsModel.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 2)
            return 64;
        NSError *error = nil;
        NSDictionary *model =
            IEBLoadStatistics(@"/var/mobile/Library/IEBNativeCapture",
                              argc == 2 ? [NSString stringWithUTF8String:argv[1]] : nil, 0, 0, &error);
        if (!model) {
            fprintf(stderr, "Statistics adapter unavailable: %s\n", error.localizedDescription.UTF8String);
            return 20;
        }
        NSUInteger percentages = 0, times = 0;
        for (NSDictionary *row in model[@"apps"]) {
            percentages += row[@"percent"] != NSNull.null;
            times += row[@"foreground"] != NSNull.null || row[@"background"] != NSNull.null;
        }
        NSMutableDictionary *safe = [NSMutableDictionary new];
        for (NSString *key in @[
                 @"state", @"range", @"window", @"screen_on", @"screen_off", @"energy_total",
                 @"allocation_estimated", @"unknown_energy_nodes", @"source_error", @"source_error_reason",
                 @"energy_error", @"levels_error", @"energy_retention_incomplete", @"activity_latest_end",
                 @"activity_pending_seconds", @"statistics_pending", @"screen_on_source",
                 @"accounted_screen_on"
             ])
            if (model[key])
                safe[key] = model[key];
        // Native journal epochs in window must not be exported.
        if (safe[@"window"]) {
            NSMutableDictionary *w = [safe[@"window"] mutableCopy];
            [w removeObjectForKey:@"epoch"];
            [w removeObjectForKey:@"current_epoch"];
            safe[@"window"] = w;
        }
        safe[@"app_count"] = @([model[@"apps"] count]);
        safe[@"percentage_count"] = @(percentages);
        safe[@"activity_app_count"] = @(times);
        safe[@"level_point_count"] = @([model[@"levels"] count]);
        safe[@"activity_bucket_count"] = @([model[@"activity_buckets"] count]);
        safe[@"feature_ready"] = @NO;
        NSData *data =
            [NSJSONSerialization dataWithJSONObject:safe
                                            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                              error:&error];
        if (!data)
            return 74;
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
        return 22;
    }
}
