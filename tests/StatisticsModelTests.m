#import "../Sources/Statistics/IEBStatisticsModel.h"
#import <math.h>
#define REQUIRE(...)                                                                                         \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Statistics FAIL %d: %s\n", __LINE__, #__VA_ARGS__);                             \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSDictionary *capture = @{
            @"available" : @YES,
            @"source_healthy" : @YES,
            @"observed_wall_time" : @150,
            @"checkpoint_native_time" : @130,
            @"window" : @{@"start" : @100, @"end" : @120, @"effective_end" : @120, @"power_complete" : @YES},
            @"range" : @{@"start" : @105, @"end" : @115},
            @"apps" : @{
                @"app.one" : @{
                    @"ScreenOnTime" : @3,
                    @"ScreenOnPluggedInTime" : @2,
                    @"BackgroundTime" : @4,
                    @"BackgroundPluggedInTime" : @1,
                    @"BackgroundAudioNowPlayingTime" : @9,
                    @"BackgroundAudioNowPlayingPluggedInTime" : @4,
                    @"BackgroundLocationTime" : @7,
                    @"BackgroundLocationPluggedInTime" : @3,
                    @"BackgroundLocationAudioTime" : @6,
                    @"BackgroundLocationAudioPluggedInTime" : @2,
                    @"BackgroundAudioPlayingTime" : @10,
                    @"BackgroundAudioPlayingTimePluggedIn" : @5
                },
                @"app.noenergy" : @{@"ScreenOnTime" : @1}
            },
            @"global_metrics" : @{@"ScreenOn" : @8, @"ScreenOff" : @2},
            @"activity_buckets" : @[],
            @"boundary_interval_count" : @1,
            @"activity_latest_end" : @110
        };
        NSDictionary *source = @{
            @"rows" : @[
                @{
                    @"ID" : @1,
                    @"timestamp" : @110,
                    @"StartOffset" : @(-10000),
                    @"EndOffset" : @10000,
                    @"Energy" : @100,
                    @"CorrectionEnergy" : @0,
                    @"TerminationRatio" : @100,
                    @"NodeID" : @1,
                    @"RootNodeID" : @99
                },
                @{
                    @"ID" : @2,
                    @"timestamp" : @110,
                    @"StartOffset" : @(-5000),
                    @"EndOffset" : @5000,
                    @"Energy" : @50,
                    @"CorrectionEnergy" : @0,
                    @"TerminationRatio" : @100,
                    @"NodeID" : @2,
                    @"RootNodeID" : @99
                }
            ],
            @"node_names" : @{@1 : @"app.one", @2 : @"system.fixture", @99 : @"energy.origin"},
            @"levels" : @[ @{@"time" : @100,
                             @"level" : @80},
                           @{@"time" : @110,
                             @"level" : @79} ]
        };
        NSError *error = nil;
        NSDictionary *model = IEBStatisticsModel(capture, source, &error);
        REQUIRE(model && !error && [model[@"apps"] count] == 3);
        REQUIRE([model[@"activity_pending_seconds"] doubleValue] == 5 &&
                [model[@"statistics_pending"] boolValue]);
        NSMutableDictionary *completeActivity = [capture mutableCopy];
        completeActivity[@"activity_latest_end"] = @115;
        REQUIRE([IEBStatisticsModel(completeActivity, source, &error)[@"activity_pending_seconds"]
                    doubleValue] == 0);
        completeActivity[@"activity_latest_end"] = NSNull.null;
        REQUIRE([IEBStatisticsModel(completeActivity, source, &error)[@"activity_pending_seconds"]
                    doubleValue] == 10);
        completeActivity[@"activity_latest_end"] = @116;
        REQUIRE(!IEBStatisticsModel(completeActivity, source, &error) && error);
        REQUIRE([model[@"energy_total"] doubleValue] == 100);
        NSDictionary *one = nil, *missing = nil;
        for (NSDictionary *row in model[@"apps"]) {
            if ([row[@"id"] isEqual:@"app.one"])
                one = row;
            if ([row[@"id"] isEqual:@"app.noenergy"])
                missing = row;
        }
        REQUIRE(one[@"percent"] != NSNull.null && [one[@"foreground"] doubleValue] == 3 &&
                [one[@"background"] doubleValue] == 4 && [one[@"percent"] doubleValue] == 50);
        REQUIRE(one[@"audio_playback"] && [one[@"audio_playback"] doubleValue] == 10);
        REQUIRE([one[@"audio_now_playing"] doubleValue] == 9 && [one[@"location"] doubleValue] == 7 &&
                [one[@"location_audio"] doubleValue] == 6);
        REQUIRE(missing[@"energy"] == NSNull.null && missing[@"background"] == NSNull.null);
        REQUIRE([model[@"allocation_estimated"] boolValue] && ![model[@"native_parity_verified"] boolValue]);
        NSMutableDictionary *liveDisplay = [source mutableCopy];
        liveDisplay[@"display_points"] = @[
            @{@"time" : @100,
              @"active" : @1},
            @{@"time" : @108,
              @"active" : @0},
            @{@"time" : @111,
              @"active" : @1}
        ];
        NSDictionary *displayModel = IEBStatisticsModel(capture, liveDisplay, &error);
        REQUIRE([displayModel[@"screen_on"] doubleValue] == 7 &&
                [displayModel[@"screen_on_source"] isEqual:@"display-events"]);
        liveDisplay[@"display_points"] = @[ @{@"time" : @108, @"active" : @1} ];
        displayModel = IEBStatisticsModel(capture, liveDisplay, &error);
        REQUIRE([displayModel[@"screen_on"] doubleValue] == 8 &&
                [displayModel[@"screen_on_source"] isEqual:@"native-activity"]);
        NSDictionary *without = IEBStatisticsModel(capture, nil, &error);
        REQUIRE(without && without[@"energy_total"] == NSNull.null);
        REQUIRE(!IEBStatisticsModel(@{}, source, &error) && error);
        NSMutableDictionary *invalid = [source mutableCopy];
        invalid[@"rows"] = @[ source[@"rows"][0], source[@"rows"][0] ];
        NSDictionary *partial = IEBStatisticsModel(capture, invalid, &error);
        REQUIRE(partial && partial[@"energy_total"] == NSNull.null && partial[@"energy_error"] &&
                [partial[@"apps"] count] == 2);
        NSMutableDictionary *brokenLevel = [source mutableCopy];
        brokenLevel[@"levels"] = @[ @{@"time" : @110, @"level" : @(-1)} ];
        partial = IEBStatisticsModel(capture, brokenLevel, &error);
        REQUIRE(partial && [partial[@"energy_total"] doubleValue] == 100 && partial[@"levels_error"] &&
                [partial[@"levels"] count] == 0);
        REQUIRE(model[@"clock_offset"] == NSNull.null);
        NSMutableDictionary *delayed = [capture mutableCopy];
        delayed[@"observed_wall_time"] = @200;
        REQUIRE(IEBStatisticsModel(delayed, source, &error)[@"clock_offset"] == NSNull.null);
        NSMutableDictionary *retained = [source mutableCopy];
        retained[@"retention_start"] = @110;
        retained[@"retention_end"] = @114;
        REQUIRE([IEBStatisticsModel(capture, retained, &error)[@"energy_coverage_known"] boolValue]);
        REQUIRE(![IEBStatisticsModel(capture, source, &error)[@"energy_coverage_known"] boolValue]);
        REQUIRE([IEBStatisticsModel(capture, retained, &error)[@"energy_retention_incomplete"] boolValue]);
        NSMutableDictionary *subset = [capture mutableCopy];
        subset[@"apps"] = @{@"app.one" : @{@"ScreenOnPluggedInTime" : @2}};
        NSDictionary *onlySubset = IEBStatisticsModel(subset, source, &error);
        NSDictionary *subsetRow = nil;
        for (NSDictionary *row in onlySubset[@"apps"])
            if ([row[@"id"] isEqual:@"app.one"])
                subsetRow = row;
        REQUIRE(subsetRow && subsetRow[@"foreground"] == NSNull.null);
        subset[@"apps"] = @{@"app.one" : @{@"ScreenOnTime" : @1, @"ScreenOnPluggedInTime" : @2}};
        REQUIRE(!IEBStatisticsModel(subset, source, &error) && error);
        NSMutableDictionary *bad = [capture mutableCopy];
        bad[@"global_metrics"] = @{@"ScreenOn" : @(NAN)};
        REQUIRE(!IEBStatisticsModel(bad, nil, &error) && error);
        NSMutableDictionary *overflow = [capture mutableCopy];
        overflow[@"apps"] = @{@"app.one" : @{@"ScreenOnTime" : @1e308, @"ScreenOnPluggedInTime" : @1e308}};
        REQUIRE(!IEBStatisticsModel(overflow, nil, &error) && error);
        puts("PASS selected-range native energy grouping, activity, unknown values and quality metadata");
        return 0;
    }
}
