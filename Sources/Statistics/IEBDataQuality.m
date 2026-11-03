#import "IEBDataQuality.h"
#import <math.h>
static BOOL Number(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]) && [n doubleValue] >= 0;
}
static BOOL HasError(id value) { return value && value != NSNull.null; }
NSDictionary *IEBDataQuality(NSDictionary *model) {
    NSDictionary *range = model[@"range"], *window = model[@"window"];
    BOOL available = Number(range[@"start"]) && Number(range[@"end"]) &&
                     [range[@"end"] doubleValue] >= [range[@"start"] doubleValue] &&
                     ![model[@"state"] isEqual:@"waiting"];
    double start = available ? [range[@"start"] doubleValue] : 0,
           end = available ? [range[@"end"] doubleValue] : 0;
    id latest = model[@"activity_latest_end"];
    BOOL recorded =
        available && Number(latest) && [latest doubleValue] >= start && [latest doubleValue] <= end;
    double pending = available ? end - (recorded ? [latest doubleValue] : start) : 0;
    BOOL recovered = [window[@"power_complete"] isEqual:@NO] && window[@"end"] &&
                     [window[@"epoch"] isKindOfClass:NSString.class] &&
                     [window[@"current_epoch"] isKindOfClass:NSString.class] &&
                     ![window[@"epoch"] isEqual:window[@"current_epoch"]];
    NSString *energy =
        !available || !Number(model[@"energy_total"]) || HasError(model[@"energy_error"]) ||
                HasError(model[@"source_error"])
            ? @"unavailable"
        : [model[@"energy_retention_incomplete"] boolValue] || ![model[@"energy_coverage_known"] isEqual:@YES]
            ? @"partial"
            : @"recorded";
    BOOL levelsAvailable = available && [model[@"levels"] isKindOfClass:NSArray.class] &&
                           [model[@"levels"] count] > 0 && !HasError(model[@"levels_error"]);
    BOOL partial = !recorded || pending > 1 || ![energy isEqual:@"recorded"] || !levelsAvailable ||
                   [model[@"state"] isEqual:@"incomplete"] || recovered || HasError(model[@"levels_error"]);
    return @{
        @"state" : !available ? @"unavailable"
        : partial             ? @"partial"
                              : @"recorded",
        @"pending_seconds" : available ? @(pending) : NSNull.null,
        @"activity_recorded_seconds" : recorded ? @([latest doubleValue] - start) : NSNull.null,
        @"range_seconds" : available ? @(end - start) : NSNull.null,
        @"energy_state" : energy,
        @"levels_available" : @(levelsAvailable),
        @"recovered_cycle" : @(recovered),
        @"app_coverage_verified" : @NO
    };
}
