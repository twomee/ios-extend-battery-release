#import "../Sources/Statistics/IEBActivityEvidence.h"
#import <math.h>
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Activity FAIL %d: %s\n", __LINE__, #c);                                         \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDate *D(double t) { return [NSDate dateWithTimeIntervalSince1970:t]; }
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSDictionary *e = IEBActivityEvidence(
            @{@"BundleID" : @"com.example.private-app",
              @"ScreenOnTime" : @10,
              @"ignored" : @99},
            D(100), D(110), &error);
        REQUIRE(e && !error && [e[@"has_app"] boolValue] && [e[@"metrics"] isEqual:@{@"ScreenOnTime" : @10}]);
        REQUIRE(!e[@"BundleID"] && ![e.description containsString:@"com.example"]);
        REQUIRE([e[@"start"] doubleValue] == 100 && [e[@"end"] doubleValue] == 110);
        e = IEBActivityEvidence(@{@"ScreenOn" : @0, @"ScreenOff" : @2.5}, D(100), D(110), &error);
        REQUIRE(e && ![e[@"has_app"] boolValue] && [e[@"metrics"] count] == 2);
        REQUIRE(!IEBActivityEvidence(@{@"Unrelated" : @5}, nil, nil, &error) && !error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @(-1)}, D(100), D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @(NAN)}, D(100), D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @YES}, D(100), D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @"12"}, D(100), D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @1}, D(100), D(100), &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @1}, nil, D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @1}, D(NAN), D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence(
                    @{@"BundleID" : @42,
                      @"BackgroundTime" : @1},
                    D(100), D(110), &error) &&
                error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOnTime" : @1}, D(100), D(110), &error) && error);
        REQUIRE(!IEBActivityEvidence((id) @[], D(100), D(110), &error) && error);
        e = IEBActivityEvidence(@{@"BundleID" : @"app", @"BackgroundTime" : @11}, D(100), D(110), &error);
        REQUIRE(e && [e[@"value_exceeds_span"] boolValue]);
        REQUIRE([NSJSONSerialization isValidJSONObject:e]);
        NSMutableDictionary *summary = [@{
            @"schema_version" : @1,
            @"writer_pid" : @123,
            @"native_hook_installed" : @YES,
            @"observer_failed" : @NO,
            @"interval_count" : @1,
            @"app_interval_count" : @1,
            @"invalid_interval_count" : @0,
            @"value_exceeds_span_count" : @0,
            @"dropped_callback_count" : @0,
            @"store_error_count" : @0,
            @"earliest_native_start" : @100,
            @"latest_native_end" : @110,
            @"observed_wall_time" : @1000,
            @"metric_totals" : @{@"ScreenOnTime" : @10},
            @"feature_ready" : @NO
        } mutableCopy];
        REQUIRE(IEBSanitizeActivitySummary(summary, &error) && !error);
        REQUIRE(IEBActivitySummaryIsCurrent(summary, 1030, YES));
        REQUIRE(!IEBActivitySummaryIsCurrent(summary, 1030, NO));
        REQUIRE(!IEBActivitySummaryIsCurrent(summary, 1066, YES));
        REQUIRE(!IEBActivitySummaryIsCurrent(summary, 999, YES));
        REQUIRE(!IEBActivitySummaryIsCurrent(summary, NAN, YES));
        summary[@"private"] = @"secret";
        REQUIRE(!IEBSanitizeActivitySummary(summary, &error) && error);
        [summary removeObjectForKey:@"private"];
        summary[@"interval_count"] = @YES;
        REQUIRE(!IEBSanitizeActivitySummary(summary, &error) && error);
        summary[@"interval_count"] = @1;
        summary[@"metric_totals"] = @{@"BundleID" : @"secret"};
        REQUIRE(!IEBSanitizeActivitySummary(summary, &error) && error);
        summary[@"metric_totals"] = @{@"ScreenOnTime" : @(INFINITY)};
        REQUIRE(!IEBSanitizeActivitySummary(summary, &error) && error);
        summary[@"metric_totals"] = @{@"ScreenOnTime" : @10};
        summary[@"feature_ready"] = @YES;
        REQUIRE(!IEBSanitizeActivitySummary(summary, &error) && error);
        REQUIRE(!IEBActivityEvidence(@{@"ScreenOn" : @0}, D(100), D(100), &error) && !error);
        puts("PASS native activity duration evidence and identity exclusion");
        return 0;
    }
}
