#import "../Sources/Statistics/IEBDataQuality.h"
#import <Foundation/Foundation.h>
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Quality FAIL %d\n", __LINE__);                                                  \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSMutableDictionary *model = [@{
            @"state" : @"observed",
            @"range" : @{@"start" : @100, @"end" : @400},
            @"window" : @{@"start" : @100, @"power_complete" : @YES},
            @"activity_latest_end" : @160,
            @"energy_retention_incomplete" : @NO,
            @"energy_error" : NSNull.null,
            @"energy_total" : @10,
            @"energy_coverage_known" : @YES,
            @"levels" : @[
                @{@"time" : @100,
                  @"level" : @80}
            ],
            @"levels_error" : NSNull.null
        } mutableCopy];
        NSDictionary *q = IEBDataQuality(model);
        C([q[@"state"] isEqual:@"partial"] && [q[@"pending_seconds"] isEqual:@240]);
        C([q[@"activity_recorded_seconds"] isEqual:@60] && ![q[@"app_coverage_verified"] boolValue]);
        model[@"activity_latest_end"] = @400;
        C([IEBDataQuality(model)[@"state"] isEqual:@"recorded"]);
        model[@"energy_total"] = NSNull.null;
        C([IEBDataQuality(model)[@"energy_state"] isEqual:@"unavailable"]);
        model[@"energy_total"] = @10;
        model[@"energy_coverage_known"] = @NO;
        C([IEBDataQuality(model)[@"energy_state"] isEqual:@"partial"]);
        model[@"energy_coverage_known"] = @YES;
        model[@"levels"] = @[];
        C(![IEBDataQuality(model)[@"levels_available"] boolValue]);
        C([IEBDataQuality(model)[@"state"] isEqual:@"partial"]);
        model[@"levels"] = @[ @{@"time" : @100, @"level" : @80} ];
        model[@"energy_retention_incomplete"] = @YES;
        C([IEBDataQuality(model)[@"energy_state"] isEqual:@"partial"]);
        model[@"energy_error"] = @"secret-path";
        C([IEBDataQuality(model)[@"energy_state"] isEqual:@"unavailable"]);
        model[@"state"] = @"incomplete";
        model[@"window"] = @{
            @"start" : @100,
            @"epoch" : @"old",
            @"current_epoch" : @"new",
            @"end" : @400,
            @"power_complete" : @NO
        };
        C([IEBDataQuality(model)[@"recovered_cycle"] boolValue]);
        model[@"window"] = @{
            @"start" : @100,
            @"epoch" : @"old",
            @"current_epoch" : @"new",
            @"end" : @400,
            @"power_complete" : @YES
        };
        C(![IEBDataQuality(model)[@"recovered_cycle"] boolValue]);
        C([IEBDataQuality(nil)[@"state"] isEqual:@"unavailable"]);
        model[@"activity_latest_end"] = NSNull.null;
        C(IEBDataQuality(model)[@"activity_recorded_seconds"] == NSNull.null);
        model[@"activity_latest_end"] = @500;
        C(IEBDataQuality(model)[@"activity_recorded_seconds"] == NSNull.null);
        puts("PASS data quality distinguishes lag, coverage, unavailable and recovered history");
        return 0;
    }
}
