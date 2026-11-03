#import "IEBStatisticsModel.h"
#import "IEBActivityEvidence.h"
#import "IEBEnergyIntervals.h"
#import "IEBScreenActivity.h"
#import <math.h>
static id Fail(NSError **error, NSString *message) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBStatisticsModel"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    return nil;
}
static BOOL Number(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]) && [n doubleValue] >= 0;
}
static BOOL Metrics(id values) {
    if (![values isKindOfClass:NSDictionary.class])
        return NO;
    for (id key in values)
        if (![IEBActivityMetricKeys() containsObject:key] || !Number(values[key]))
            return NO;
    return YES;
}
// Native plugged values are subsets of total values, not disjoint durations.
static id Total(NSDictionary *metrics, NSString *key, NSString *pluggedKey) {
    id total = metrics[key], subset = metrics[pluggedKey];
    if (!total)
        return NSNull.null;
    double value = [total doubleValue];
    if (value > 86400000 || (subset && [subset doubleValue] > value + 0.001))
        return nil;
    return total;
}
static NSDictionary *EnergyComponent(NSDictionary *source, double start, double end, NSError **error) {
    if (![source isKindOfClass:NSDictionary.class] || source[@"energy_error"] ||
        ![source[@"rows"] isKindOfClass:NSArray.class] ||
        ![source[@"node_names"] isKindOfClass:NSDictionary.class])
        return Fail(error, @"Native energy unavailable");
    NSDictionary *total = IEBEnergyForWindow(source[@"rows"], start, end, error);
    if (!total)
        return nil;
    NSMutableDictionary *grouped = [NSMutableDictionary new], *energies = [NSMutableDictionary new];
    NSMutableSet *unknown = [NSMutableSet new];
    for (NSDictionary *row in source[@"rows"]) {
        id recipient = row[@"NodeID"];
        if (!Number(recipient) || [recipient doubleValue] != floor([recipient doubleValue]))
            return Fail(error, @"Invalid recipient node identity");
        id name = source[@"node_names"][recipient];
        if (name && (![name isKindOfClass:NSString.class] || ![name length] || [name length] > 4096))
            return Fail(error, @"Invalid recipient node name");
        if (!name) {
            [unknown addObject:recipient];
            name = [@"IEB.Unknown." stringByAppendingString:[recipient description]];
        }
        if (!grouped[name])
            grouped[name] = [NSMutableArray new];
        [grouped[name] addObject:row];
    }
    for (NSString *identity in grouped) {
        NSDictionary *energy = IEBEnergyForWindow(grouped[identity], start, end, error);
        if (!energy)
            return nil;
        energies[identity] = energy[@"estimated_native_units"];
    }
    return @{
        @"total" : [source[@"rows"] count] ? total : NSNull.null,
        @"energies" : energies,
        @"unknown" : @(unknown.count)
    };
}
static NSArray *LevelComponent(NSDictionary *source, double end, NSError **error) {
    if (![source isKindOfClass:NSDictionary.class] || source[@"levels_error"] ||
        ![source[@"levels"] isKindOfClass:NSArray.class] || [source[@"levels"] count] > 200000)
        return Fail(error, @"Battery levels unavailable");
    double previous = 0;
    for (id point in source[@"levels"]) {
        if (![point isKindOfClass:NSDictionary.class] || !Number(point[@"time"]) ||
            !Number(point[@"level"]) || [point[@"time"] doubleValue] <= 0 ||
            [point[@"time"] doubleValue] < previous || [point[@"time"] doubleValue] > end ||
            [point[@"level"] doubleValue] > 100)
            return Fail(error, @"Invalid battery level graph");
        previous = [point[@"time"] doubleValue];
    }
    return source[@"levels"];
}
NSDictionary *IEBStatisticsModel(NSDictionary *capture, NSDictionary *source, NSError **error) {
    if (error)
        *error = nil;
    if (![capture isKindOfClass:NSDictionary.class] || ![capture[@"available"] isKindOfClass:NSNumber.class])
        return Fail(error, @"Missing captured statistics");
    if (![capture[@"available"] boolValue])
        return @{@"state" : @"waiting", @"apps" : @[], @"native_parity_verified" : @NO};
    source = [source isKindOfClass:NSDictionary.class] ? source : nil;
    NSDictionary *range = capture[@"range"], *window = capture[@"window"], *activity = capture[@"apps"],
                 *global = capture[@"global_metrics"];
    if (![range isKindOfClass:NSDictionary.class] || ![window isKindOfClass:NSDictionary.class] ||
        !Number(range[@"start"]) || !Number(range[@"end"]) || !Number(window[@"start"]) ||
        !Number(window[@"effective_end"]) || ![activity isKindOfClass:NSDictionary.class] || !Metrics(global))
        return Fail(error, @"Invalid captured range or metrics");
    double a = [range[@"start"] doubleValue], b = [range[@"end"] doubleValue];
    if (a <= 0 || b <= a || a < [window[@"start"] doubleValue] ||
        b > [window[@"effective_end"] doubleValue] || !isfinite(b - a))
        return Fail(error, @"Invalid statistics selection");
    for (id identity in activity)
        if (![identity isKindOfClass:NSString.class] || ![identity length] || [identity length] > 4096 ||
            !Metrics(activity[identity]))
            return Fail(error, @"Invalid app activity");
    NSError *energyError = nil, *levelError = nil;
    NSDictionary *component = EnergyComponent(source, a, b, &energyError);
    NSDictionary *energies = component[@"energies"] ?: @{};
    NSMutableSet *identities = [NSMutableSet setWithArray:activity.allKeys];
    [identities addObjectsFromArray:energies.allKeys];
    NSDictionary *total = component[@"total"] == NSNull.null ? nil : component[@"total"];
    NSArray *levels = LevelComponent(source, b, &levelError) ?: @[];
    BOOL coverageKnown = Number(source[@"retention_start"]) && Number(source[@"retention_end"]) &&
                         [source[@"retention_start"] doubleValue] <= [source[@"retention_end"] doubleValue];
    BOOL retentionIncomplete = coverageKnown && ([source[@"retention_start"] doubleValue] > a ||
                                                 [source[@"retention_end"] doubleValue] < b);
    NSMutableArray *apps = [NSMutableArray new];
    double denominator = [total[@"estimated_native_units"] doubleValue];
    for (NSString *identity in identities) {
        NSDictionary *m = activity[identity] ?: @{};
        NSMutableDictionary *durations = [NSMutableDictionary new];
        for (NSArray *mapping in @[
                 @[ @"foreground", @"ScreenOnTime", @"ScreenOnPluggedInTime" ],
                 @[ @"background", @"BackgroundTime", @"BackgroundPluggedInTime" ],
                 @[
                     @"audio_now_playing", @"BackgroundAudioNowPlayingTime",
                     @"BackgroundAudioNowPlayingPluggedInTime"
                 ],
                 @[
                     @"audio_playback", @"BackgroundAudioPlayingTime", @"BackgroundAudioPlayingTimePluggedIn"
                 ],
                 @[ @"location", @"BackgroundLocationTime", @"BackgroundLocationPluggedInTime" ],
                 @[
                     @"location_audio", @"BackgroundLocationAudioTime",
                     @"BackgroundLocationAudioPluggedInTime"
                 ]
             ]) {
            id value = Total(m, mapping[1], mapping[2]);
            if (!value)
                return Fail(error, @"Invalid activity total or plugged subset");
            durations[mapping[0]] = value;
        }
        id percent = NSNull.null;
        if (energies[identity] && denominator > 0) {
            double p = [energies[identity] doubleValue] / denominator * 100;
            if (!isfinite(p) || p < 0 || p > 100.000001)
                return Fail(error, @"Invalid relative energy");
            percent = @(MIN(100, p));
        }
        NSMutableDictionary *row = [@{
            @"id" : identity,
            @"metrics" : m,
            @"energy" : total ? energies[identity] ?: NSNull.null : NSNull.null,
            @"percent" : percent
        } mutableCopy];
        [row addEntriesFromDictionary:durations];
        [apps addObject:[row copy]];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        double vx = x[@"percent"] == NSNull.null ? -1 : [x[@"percent"] doubleValue],
               vy = y[@"percent"] == NSNull.null ? -1 : [y[@"percent"] doubleValue];
        if (vx != vy)
            return vx > vy ? NSOrderedAscending : NSOrderedDescending;
        vx = x[@"foreground"] == NSNull.null ? -1 : [x[@"foreground"] doubleValue];
        vy = y[@"foreground"] == NSNull.null ? -1 : [y[@"foreground"] doubleValue];
        return vx != vy ? (vx > vy ? NSOrderedAscending : NSOrderedDescending) : [x[@"id"] compare:y[@"id"]];
    }];
    id activityEnd = capture[@"activity_latest_end"];
    if (activityEnd && activityEnd != NSNull.null &&
        (!Number(activityEnd) || [activityEnd doubleValue] < a || [activityEnd doubleValue] > b))
        return Fail(error, @"Invalid latest activity time");
    double pending = b - ((activityEnd && activityEnd != NSNull.null) ? [activityEnd doubleValue] : a);
    NSError *displayError = nil;
    NSDictionary *display = IEBScreenActivity(source[@"display_points"], a, b,
                                              capture[@"activity_buckets"] ?: @[], &displayError);
    BOOL complete = [capture[@"source_healthy"] boolValue] && [window[@"power_complete"] boolValue];
    return @{
        @"state" : complete ? @"observed" : @"incomplete",
        @"apps" : apps,
        @"range" : range,
        @"window" : window,
        @"clock_offset" : NSNull.null,
        @"activity_latest_end" : activityEnd ?: NSNull.null,
        @"activity_pending_seconds" : @(pending),
        @"statistics_pending" : @(pending > 1 || retentionIncomplete),
        @"energy_retention_incomplete" : @(retentionIncomplete),
        @"energy_coverage_known" : @(coverageKnown),
        @"energy_error" : energyError ? energyError.localizedDescription : NSNull.null,
        @"levels_error" : levelError ? levelError.localizedDescription : NSNull.null,
        @"screen_on" : display[@"screen_on"] ?: global[@"ScreenOn"] ?: NSNull.null,
        @"screen_on_source":display ? @"display-events" : @"native-activity",
        @"accounted_screen_on":global[@"ScreenOn"] ?: NSNull.null,
        @"screen_off" : global[@"ScreenOff"] ?: NSNull.null,
        @"activity_buckets" : display[@"buckets"] ?: capture[@"activity_buckets"] ?: @[],
        @"levels" : levels,
        @"energy_total" : total[@"estimated_native_units"] ?: NSNull.null,
        @"allocation_estimated" : @([capture[@"boundary_interval_count"] integerValue] > 0 ||
                                    [total[@"boundary_interval_count"] integerValue] > 0),
        @"unknown_energy_nodes" : component[@"unknown"] ?: @0,
        @"native_parity_verified" : @NO,
        @"source_coverage_verified" : @NO
    };
}
