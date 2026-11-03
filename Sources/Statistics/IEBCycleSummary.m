#import "IEBCycleHistory.h"
#import <math.h>
static BOOL Number(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]) && [n doubleValue] >= 0;
}
static id Invalid(NSError **error, NSString *reason) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBCycleHistory"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : reason}];
    return nil;
}
NSDictionary *IEBSummarizeClosedCycle(NSDictionary *capture, NSError **error) {
    if (error)
        *error = nil;
    if (![capture isKindOfClass:NSDictionary.class] || ![capture[@"window"] isKindOfClass:NSDictionary.class])
        return Invalid(error, @"Invalid cycle capture");
    NSDictionary *w = capture[@"window"];
    if (!w[@"start"] || !w[@"end"])
        return nil;
    if (!Number(w[@"start"]) || !Number(w[@"end"]) || [w[@"start"] doubleValue] <= 0 ||
        [w[@"end"] doubleValue] < [w[@"start"] doubleValue] || ![w[@"epoch"] isKindOfClass:NSString.class] ||
        ![w[@"epoch"] length] || [w[@"epoch"] length] > 128 ||
        ![w[@"power_complete"] isKindOfClass:NSNumber.class] ||
        ([w[@"power_complete"] doubleValue] != 0 && [w[@"power_complete"] doubleValue] != 1))
        return Invalid(error, @"Invalid closed cycle boundaries");
    double start = [w[@"start"] doubleValue], end = [w[@"end"] doubleValue], duration = end - start;
    // A gap at the detach edge has no observed extent to save.
    if (duration == 0)
        return nil;
    if (!isfinite(duration))
        return Invalid(error, @"Invalid cycle duration");
    id metrics = capture[@"global_metrics"];
    if (metrics && ![metrics isKindOfClass:NSDictionary.class])
        return Invalid(error, @"Invalid cycle activity");
    id on = metrics[@"ScreenOn"], off = metrics[@"ScreenOff"], latest = capture[@"activity_latest_end"];
    if ((on && !Number(on)) || (off && !Number(off)) ||
        (latest && latest != NSNull.null &&
         (!Number(latest) || [latest doubleValue] < start || [latest doubleValue] > end)))
        return Invalid(error, @"Invalid cycle measurements");
    double pending = end - ((latest && latest != NSNull.null) ? [latest doubleValue] : start);
    return @{
        @"id" : [NSString
            stringWithFormat:@"%lu:%@:%.17g", (unsigned long)[w[@"epoch"] length], w[@"epoch"], start],
        @"start" : @(start),
        @"end" : @(end),
        @"duration" : @(duration),
        @"screen_on" : on ?: NSNull.null,
        @"screen_off" : off ?: NSNull.null,
        @"activity_pending_seconds" : @(pending),
        @"power_complete" : @([w[@"power_complete"] boolValue])
    };
}
static id Delta(NSDictionary *a, NSDictionary *b, NSString *key) {
    if (!Number(a[key]) || !Number(b[key]))
        return NSNull.null;
    double delta = [a[key] doubleValue] - [b[key] doubleValue];
    return isfinite(delta) ? @(delta) : NSNull.null;
}
static BOOL EnergyComparable(NSDictionary *record) {
    if (!Number(record[@"duration"]) || [record[@"duration"] doubleValue] <= 0 ||
        !Number(record[@"energy_total"]) || !Number(record[@"energy_per_hour"]))
        return NO;
    double normalized = [record[@"energy_total"] doubleValue] / ([record[@"duration"] doubleValue] / 3600.0);
    if (!isfinite(normalized) ||
        fabs(normalized - [record[@"energy_per_hour"] doubleValue]) > MAX(1.0, fabs(normalized)) * 1e-9)
        return NO;
    return [record[@"power_complete"] isEqual:@YES] && [record[@"energy_coverage_known"] isEqual:@YES] &&
           [record[@"energy_partial"] isEqual:@NO] && Number(record[@"duration"]) &&
           [record[@"duration"] doubleValue] > 0 && Number(record[@"energy_total"]) &&
           Number(record[@"energy_per_hour"]);
}
NSDictionary *IEBCompareCycleSummaries(NSDictionary *a, NSDictionary *b) {
    a = [a isKindOfClass:NSDictionary.class] ? a : @{};
    b = [b isKindOfClass:NSDictionary.class] ? b : @{};
    BOOL comparable = EnergyComparable(a) && EnergyComparable(b);
    id energy = comparable ? Delta(a, b, @"energy_per_hour") : NSNull.null;
    id relative = NSNull.null;
    // Product eligibility rule: do not extrapolate sub-minute cycles into a
    // user-facing rate comparison. Longer cycles still remain estimates.
    if (comparable && [a[@"duration"] doubleValue] >= 60 && [b[@"duration"] doubleValue] >= 60 &&
        [b[@"energy_per_hour"] doubleValue] > 0) {
        double percent =
            ([a[@"energy_per_hour"] doubleValue] / [b[@"energy_per_hour"] doubleValue] - 1) * 100;
        if (isfinite(percent))
            relative = @(percent);
    }
    return @{
        @"energy_rate_relative_percent" : relative,
        @"duration_delta" : Delta(a, b, @"duration"),
        @"screen_on_delta" : Delta(a, b, @"screen_on"),
        @"screen_off_delta" : Delta(a, b, @"screen_off"),
        @"energy_per_hour_delta" : energy,
        @"comparable_energy" : @(comparable && energy != NSNull.null)
    };
}
