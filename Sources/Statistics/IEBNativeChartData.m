#import "IEBNativeChartData.h"
#import <math.h>
static BOOL Number(id v) {
    return [v isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)v) != CFBooleanGetTypeID() &&
           isfinite([v doubleValue]);
}
static id Fail(NSError **error) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBNativeChartData"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : @"Invalid native chart input"}];
    return nil;
}
NSDictionary *IEBNativeChartData(NSDictionary *overview, NSError **error) {
    if (error)
        *error = nil;
    NSDictionary *range = overview[@"range"];
    if (!Number(range[@"start"]) || !Number(range[@"end"]))
        return Fail(error);
    double start = [range[@"start"] doubleValue], end = [range[@"end"] doubleValue];
    NSArray *points = overview[@"levels"], *activity = overview[@"activity_buckets"];
    if (start <= 0 || end <= start || end - start > 864000 || ![points isKindOfClass:NSArray.class] ||
        points.count > 200000 || ![activity isKindOfClass:NSArray.class] || activity.count > 96)
        return Fail(error);
    double previous = 0;
    for (NSDictionary *p in points) {
        if (![p isKindOfClass:NSDictionary.class] || !Number(p[@"time"]) || !Number(p[@"level"]) ||
            [p[@"time"] doubleValue] <= 0 || [p[@"time"] doubleValue] < previous ||
            [p[@"time"] doubleValue] > end || [p[@"level"] doubleValue] < 0 ||
            [p[@"level"] doubleValue] > 100)
            return Fail(error);
        previous = [p[@"time"] doubleValue];
    }
    previous = start;
    for (NSDictionary *p in activity) {
        if (![p isKindOfClass:NSDictionary.class] || !Number(p[@"start"]) || !Number(p[@"end"]) ||
            [p[@"start"] doubleValue] < previous || [p[@"end"] doubleValue] <= [p[@"start"] doubleValue] ||
            [p[@"end"] doubleValue] > end)
            return Fail(error);
        for (NSString *key in @[ @"ScreenOn", @"ScreenOff" ])
            if (p[key] != NSNull.null && (!Number(p[key]) || [p[key] doubleValue] < 0))
                return Fail(error);
        previous = [p[@"end"] doubleValue];
    }
    id nativeEnd = overview[@"native_end_of_day"];
    if (nativeEnd && (!Number(nativeEnd) || [nativeEnd doubleValue] <= 86400))
        return Fail(error);
    double dayEnd = nativeEnd ? [nativeEnd doubleValue] : ceil(end / 3600) * 3600;
    // Preserve the native hour lattice, but do not freeze a live cycle at an old snapshot boundary.
    if (nativeEnd && end > dayEnd)
        dayEnd += ceil((end - dayEnd) / 3600) * 3600;
    double reference = dayEnd - 86400;
    NSMutableArray *levels = [NSMutableArray new], *on = [NSMutableArray new], *off = [NSMutableArray new],
                   *buckets = [NSMutableArray new];
    for (int i = 0; i < 96; i++) {
        double a = reference + i * 900, b = a + 900;
        id level = @(-1);
        for (NSDictionary *p in points) {
            double t = [p[@"time"] doubleValue];
            if (t >= MAX(a, start) && t < b)
                level = p[@"level"];
            else if (a <= start && b > start && t < start)
                level = p[@"level"];
        }
        [levels addObject:@[ level, @0 ]];
    }
    double totalOn = 0, totalOff = 0;
    BOOL completeOn = YES, completeOff = YES;
    for (int i = 0; i < 24; i++) {
        double lo = MAX(start, reference + i * 3600), hi = MIN(end, reference + (i + 1) * 3600), screenOn = 0,
               screenOff = 0, cursor = lo;
        BOOL knownOn = hi > lo, knownOff = hi > lo;
        for (NSDictionary *p in activity) {
            double a = MAX(lo, [p[@"start"] doubleValue]), b = MIN(hi, [p[@"end"] doubleValue]);
            if (b <= a)
                continue;
            if (a > cursor + 0.000001)
                knownOn = knownOff = NO;
            cursor = b;
            knownOn &= Number(p[@"ScreenOn"]);
            knownOff &= Number(p[@"ScreenOff"]);
            double ratio = (b - a) / ([p[@"end"] doubleValue] - [p[@"start"] doubleValue]);
            if (Number(p[@"ScreenOn"]))
                screenOn += [p[@"ScreenOn"] doubleValue] * ratio;
            if (Number(p[@"ScreenOff"]))
                screenOff += [p[@"ScreenOff"] doubleValue] * ratio;
        }
        if (cursor < hi - 0.000001)
            knownOn = knownOff = NO;
        [on addObject:knownOn ? @(screenOn) : @(-1)];
        [off addObject:knownOff ? @(screenOff) : @(-1)];
        [buckets addObject:hi > lo ? @{@"start" : @(lo), @"end" : @(hi)} : NSNull.null];
        if (hi > lo) {
            completeOn &= knownOn;
            completeOff &= knownOff;
            totalOn += screenOn;
            totalOff += screenOff;
        }
    }
    NSDictionary *data = @{
        @"PLBatteryUIBatteryLevelsKey" : levels,
        @"PLBatteryUIChargingIntervalsKey" : @[],
        @"PLBatteryUIScreenOnTimeKey" :
            @{@"PLBatteryUIGraphHourly" : on, @"PLBatteryUIGraphTotal" : completeOn ? @(totalOn) : @(-1)},
        @"PLBatteryUIScreenOffTimeKey" :
            @{@"PLBatteryUIGraphHourly" : off, @"PLBatteryUIGraphTotal" : completeOff ? @(totalOff) : @(-1)}
    };
    return @{
        @"dataset" : @{
            @"PLBatteryUIGraph24hrs" : data,
            @"PLBatteryUIGraphDays" : @[ @{}, @{}, @{}, @{}, @{}, @{}, @{}, @{}, @{}, @{} ]
        },
        @"end_of_day" : [NSDate dateWithTimeIntervalSince1970:dayEnd],
        @"reference" : @(reference),
        @"buckets" : buckets,
        @"visible_start" : @(MAX(start, reference)),
        @"truncated" : @(start < reference)
    };
}
NSDictionary *IEBNativeChartSelection(NSDictionary *data, NSNumber *index) {
    if (!Number(index) || index.doubleValue != floor(index.doubleValue) || index.integerValue < 0 ||
        index.integerValue >= 24)
        return nil;
    NSArray *buckets = data[@"buckets"];
    if (![buckets isKindOfClass:NSArray.class] || buckets.count != 24)
        return nil;
    id value = buckets[(NSUInteger)index.integerValue];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
