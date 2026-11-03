#import "IEBActivityEvidence.h"
#import <math.h>
NSArray<NSString *> *IEBActivityMetricKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            @"ScreenOn", @"ScreenOff", @"ScreenOnTime", @"ScreenOnPluggedInTime", @"BackgroundTime",
            @"BackgroundPluggedInTime", @"BackgroundAudioNowPlayingTime",
            @"BackgroundAudioNowPlayingPluggedInTime", @"BackgroundAudioPlayingTime",
            @"BackgroundAudioPlayingTimePluggedIn", @"BackgroundLocationTime",
            @"BackgroundLocationPluggedInTime", @"BackgroundLocationAudioTime",
            @"BackgroundLocationAudioPluggedInTime"
        ];
    });
    return keys;
}
static id Invalid(NSError **error, NSString *reason) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBActivityEvidence"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : reason}];
    return nil;
}
NSDictionary *IEBActivityEvidence(NSDictionary *entry, NSDate *start, NSDate *end, NSError **error) {
    if (error)
        *error = nil;
    if (![entry isKindOfClass:NSDictionary.class])
        return Invalid(error, @"Invalid activity aggregate");
    NSMutableDictionary *metrics = [NSMutableDictionary new];
    BOOL appMetrics = NO, nonzero = NO;
    for (NSString *key in IEBActivityMetricKeys()) {
        id number = entry[key];
        if (!number)
            continue;
        if (![number isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID() ||
            !isfinite([number doubleValue]) || [number doubleValue] < 0)
            return Invalid(error, @"Invalid activity duration");
        metrics[key] = number;
        nonzero |= [number doubleValue] > 0;
        appMetrics |= ![key isEqual:@"ScreenOn"] && ![key isEqual:@"ScreenOff"];
    }
    if (!metrics.count)
        return nil;
    id bundle = entry[@"BundleID"];
    if ((bundle &&
         (![bundle isKindOfClass:NSString.class] || [bundle length] == 0 || [bundle length] > 1024)) ||
        (appMetrics && !bundle))
        return Invalid(error, @"Missing or invalid app identity");
    if (![start isKindOfClass:NSDate.class] || ![end isKindOfClass:NSDate.class])
        return Invalid(error, @"Missing activity interval");
    double a = start.timeIntervalSince1970, b = end.timeIntervalSince1970;
    if (!isfinite(a) || !isfinite(b) || a <= 0 || b < a || !isfinite(b - a))
        return Invalid(error, @"Invalid activity interval");
    if (a == b)
        return nonzero ? Invalid(error, @"Nonzero activity has empty interval") : nil;
    BOOL exceeds = NO;
    for (NSNumber *number in metrics.allValues)
        exceeds |= number.doubleValue > b - a + 0.001;
    return @{
        @"schema_version" : @1,
        @"start" : @(a),
        @"end" : @(b),
        @"has_app" : @(bundle != nil),
        @"metrics" : [metrics copy],
        @"value_exceeds_span" : @(exceeds)
    };
}

static BOOL ValidNumber(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]) && [n doubleValue] >= 0;
}
NSDictionary *IEBSanitizeActivitySummary(id summary, NSError **error) {
    if (error)
        *error = nil;
    if (![summary isKindOfClass:NSDictionary.class] || [summary count] != 15)
        return Invalid(error, @"Invalid activity summary shape");
    NSMutableDictionary *safe = [NSMutableDictionary new];
    for (NSString *key in @[
             @"schema_version", @"writer_pid", @"interval_count", @"app_interval_count",
             @"invalid_interval_count", @"value_exceeds_span_count", @"dropped_callback_count",
             @"store_error_count", @"earliest_native_start", @"latest_native_end", @"observed_wall_time"
         ]) {
        id n = summary[key];
        if (!ValidNumber(n))
            return Invalid(error, @"Invalid activity summary number");
        if ([key hasSuffix:@"count"] &&
            ([n doubleValue] != floor([n doubleValue]) || [n doubleValue] > 9007199254740991.0))
            return Invalid(error, @"Invalid activity summary count");
        safe[key] = n;
    }
    if ([safe[@"writer_pid"] doubleValue] < 1 || [safe[@"writer_pid"] doubleValue] > INT_MAX ||
        [safe[@"writer_pid"] doubleValue] != floor([safe[@"writer_pid"] doubleValue]) ||
        ![safe[@"schema_version"] isEqual:@1] || [safe[@"observed_wall_time"] doubleValue] <= 0 ||
        [safe[@"app_interval_count"] doubleValue] > [safe[@"interval_count"] doubleValue] ||
        [safe[@"value_exceeds_span_count"] doubleValue] > [safe[@"interval_count"] doubleValue])
        return Invalid(error, @"Invalid activity summary version or totals");
    double a = [safe[@"earliest_native_start"] doubleValue], b = [safe[@"latest_native_end"] doubleValue];
    if ([safe[@"interval_count"] doubleValue] == 0 ? (a != 0 || b != 0) : (a <= 0 || b <= a))
        return Invalid(error, @"Invalid activity summary interval bounds");
    for (NSString *key in @[ @"native_hook_installed", @"observer_failed", @"feature_ready" ]) {
        id n = summary[key];
        if (![n isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID())
            return Invalid(error, @"Invalid activity summary flag");
        safe[key] = n;
    }
    if ([safe[@"feature_ready"] boolValue])
        return Invalid(error, @"Diagnostic cannot certify feature readiness");
    id metrics = summary[@"metric_totals"];
    if (![metrics isKindOfClass:NSDictionary.class] || [metrics count] > IEBActivityMetricKeys().count)
        return Invalid(error, @"Invalid activity metric totals");
    NSMutableDictionary *values = [NSMutableDictionary new];
    for (id key in metrics) {
        if (![IEBActivityMetricKeys() containsObject:key] || !ValidNumber(metrics[key]))
            return Invalid(error, @"Unknown or invalid activity metric total");
        values[key] = metrics[key];
    }
    safe[@"metric_totals"] = [values copy];
    return [safe copy];
}

BOOL IEBActivitySummaryIsCurrent(NSDictionary *summary, double now, BOOL writerExists) {
    if (!writerExists || !isfinite(now) || now <= 0)
        return NO;
    id observed = summary[@"observed_wall_time"];
    if (!ValidNumber(observed))
        return NO;
    double age = now - [observed doubleValue];
    return age >= 0 && age <= 65;
}
