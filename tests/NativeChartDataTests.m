#import "../Sources/Statistics/IEBNativeChartData.h"
#import <math.h>
#define CHECK(x)                                                                                             \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Native chart FAIL %d\n", __LINE__);                                             \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSDictionary *model = @{
            @"range" : @{@"start" : @100000, @"end" : @103685},
            @"levels" : @[ @{@"time" : @100000,
                             @"level" : @80},
                           @{@"time" : @103600,
                             @"level" : @70} ],
            @"activity_buckets" : @[
                @{@"start" : @100000,
                  @"end" : @103685,
                  @"ScreenOn" : @3000,
                  @"ScreenOff" : @60}
            ]
        };
        NSError *error = nil;
        NSDictionary *graph = IEBNativeChartData(model, &error);
        CHECK(graph && !error);
        CHECK([graph[@"dataset"][@"PLBatteryUIGraph24hrs"][@"PLBatteryUIBatteryLevelsKey"] count] == 96);
        CHECK([graph[@"buckets"] count] == 24);
        NSDictionary *data = graph[@"dataset"][@"PLBatteryUIGraph24hrs"];
        NSArray *on = data[@"PLBatteryUIScreenOnTimeKey"][@"PLBatteryUIGraphHourly"];
        double total = 0;
        for (NSNumber *n in on)
            if (n.doubleValue >= 0)
                total += n.doubleValue;
        CHECK(fabs(total - 3000) < 0.000001);
        CHECK([on[0] doubleValue] == -1);
        NSDictionary *last = IEBNativeChartSelection(graph, @23);
        CHECK([last[@"start"] doubleValue] >= 100000 && [last[@"end"] doubleValue] == 103685);
        CHECK(!IEBNativeChartSelection(graph, @0));
        CHECK(!IEBNativeChartSelection(graph, @24));
        CHECK(!IEBNativeChartSelection(graph, @(-1)));
        CHECK(!IEBNativeChartSelection(graph, @1.5));
        CHECK([data[@"PLBatteryUIBatteryLevelsKey"][0][0] doubleValue] == -1);
        NSMutableDictionary *anchored = [model mutableCopy];
        anchored[@"native_end_of_day"] = @108000;
        NSDictionary *aligned = IEBNativeChartData(anchored, &error);
        CHECK(aligned && [aligned[@"end_of_day"] timeIntervalSince1970] == 108000);
        CHECK([aligned[@"reference"] doubleValue] == 21600);
        CHECK(!IEBNativeChartSelection(aligned, @23));
        CHECK([IEBNativeChartSelection(aligned, @22)[@"end"] doubleValue] == 103685);
        anchored[@"native_end_of_day"] = @103680;
        aligned = IEBNativeChartData(anchored, &error);
        CHECK(aligned && [aligned[@"end_of_day"] timeIntervalSince1970] == 107280);
        anchored[@"range"] = @{@"start" : @107990, @"end" : @108010};
        anchored[@"levels"] = @[ @{@"time" : @108005, @"level" : @60} ];
        anchored[@"activity_buckets"] = @[];
        anchored[@"native_end_of_day"] = @108000;
        aligned = IEBNativeChartData(anchored, &error);
        CHECK(aligned && [aligned[@"end_of_day"] timeIntervalSince1970] == 111600);
        CHECK([IEBNativeChartSelection(aligned, @23)[@"end"] doubleValue] == 108010);
        CHECK([aligned[@"dataset"][@"PLBatteryUIGraph24hrs"][@"PLBatteryUIBatteryLevelsKey"][92][0]
                  doubleValue] == 60);
        anchored[@"native_end_of_day"] = @(-1);
        CHECK(!IEBNativeChartData(anchored, &error) && error);
        CHECK(!IEBNativeChartData(@{}, &error) && error);
        NSMutableDictionary *bad = [model mutableCopy];
        bad[@"levels"] = @[ @{@"time" : @100000, @"level" : @101} ];
        CHECK(!IEBNativeChartData(bad, &error) && error);
        bad = [model mutableCopy];
        bad[@"activity_buckets"] = @[
            @{@"start" : @100000,
              @"end" : @103685,
              @"ScreenOn" : NSNull.null,
              @"ScreenOff" : @0}
        ];
        graph = IEBNativeChartData(bad, &error);
        CHECK(graph && !error);
        CHECK([graph[@"dataset"][@"PLBatteryUIGraph24hrs"][@"PLBatteryUIScreenOnTimeKey"]
                    [@"PLBatteryUIGraphHourly"][23] doubleValue] == -1);
        bad = [model mutableCopy];
        bad[@"activity_buckets"] = @[
            @{@"start" : @100000,
              @"end" : @103685,
              @"ScreenOn" : @3000,
              @"ScreenOff" : NSNull.null}
        ];
        graph = IEBNativeChartData(bad, &error);
        CHECK([graph[@"dataset"][@"PLBatteryUIGraph24hrs"][@"PLBatteryUIScreenOnTimeKey"]
                    [@"PLBatteryUIGraphHourly"][23] doubleValue] > 0);
        CHECK([graph[@"dataset"][@"PLBatteryUIGraph24hrs"][@"PLBatteryUIScreenOnTimeKey"]
                    [@"PLBatteryUIGraphTotal"] doubleValue] == 3000);
        CHECK([graph[@"dataset"][@"PLBatteryUIGraph24hrs"][@"PLBatteryUIScreenOffTimeKey"]
                    [@"PLBatteryUIGraphHourly"][23] doubleValue] == -1);
        puts("PASS native chart bounds, missing slots, energy-independent activity and selection clipping");
        return 0;
    }
}
