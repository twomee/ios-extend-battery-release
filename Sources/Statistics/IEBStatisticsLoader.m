#import "IEBCaptureSnapshot.h"
#import "IEBCycleHistory.h"
#import "IEBEnergyIntervalReader.h"
#import "IEBEnergyIntervals.h"
#import "IEBScreenActivity.h"
#import "IEBStatisticsModel.h"
#import <math.h>
static NSString *Database(void) {
    NSString *root = @"/var/containers/Shared/SystemGroup";
    NSError *error = nil;
    NSArray *groups = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:&error];
    if (error || groups.count > 1024)
        return nil;
    NSString *found = nil;
    for (NSString *group in groups) {
        if (![group isKindOfClass:NSString.class] || [group containsString:@"/"] || [group isEqual:@"."] ||
            [group isEqual:@".."])
            continue;
        NSString *path = [[root stringByAppendingPathComponent:group]
            stringByAppendingPathComponent:@"Library/BatteryLife/CurrentPowerlog.PLSQL"];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            if (found)
                return nil;
            found = path;
        }
    }
    return found;
}
NSDictionary *IEBLoadStatistics(NSString *directory, NSString *database, double start, double end,
                                NSError **error) {
    if (error)
        *error = nil;
    NSDictionary *capture = start || end ? IEBReadCaptureSelection(directory, start, end, error)
                                         : IEBReadCaptureSnapshot(directory, error);
    if (!capture)
        return nil;
    NSError *sourceError = nil;
    NSDictionary *source = nil;
    if ([capture[@"available"] boolValue]) {
        database = database ?: Database();
        if (database)
            source = IEBReadEnergyAndLevels(database, [capture[@"range"][@"start"] doubleValue],
                                            [capture[@"range"][@"end"] doubleValue], &sourceError);
    }
    if (database && [capture[@"available"] boolValue]) {
        NSError *displayError = nil;
        NSDictionary *display = IEBReadDisplayActivity(database, [capture[@"range"][@"start"] doubleValue],
                                                       [capture[@"range"][@"end"] doubleValue],
                                                       capture[@"activity_buckets"] ?: @[], &displayError);
        if (display) {
            NSMutableDictionary *enriched = [source mutableCopy] ?: [NSMutableDictionary new];
            enriched[@"display_points"] = display[@"points"];
            source = enriched;
        }
    }
    NSDictionary *model = IEBStatisticsModel(capture, source, error);
    if (!model)
        return nil;
    NSMutableDictionary *result = [model mutableCopy];
    if ([capture[@"available"] boolValue] && !source) {
        result[@"source_error"] = @"Native energy and battery levels are unavailable";
        result[@"source_error_reason"] =
            sourceError.localizedDescription ?: @"Cannot resolve a unique native database";
    }
    return [result copy];
}

static BOOL HistoryNumber(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]) && [n doubleValue] >= 0;
}
NSDictionary *IEBLoadHistoricalCycle(NSDictionary *record, NSString *database, NSError **error) {
    if (error)
        *error = nil;
    if (![record isKindOfClass:NSDictionary.class] || !HistoryNumber(record[@"start"]) ||
        !HistoryNumber(record[@"end"]) || !HistoryNumber(record[@"duration"]) ||
        [record[@"start"] doubleValue] <= 0 ||
        [record[@"end"] doubleValue] <= [record[@"start"] doubleValue] ||
        [record[@"duration"] doubleValue] != [record[@"end"] doubleValue] - [record[@"start"] doubleValue]) {
        if (error)
            *error =
                [NSError errorWithDomain:@"IEBCycleHistory"
                                    code:1
                                userInfo:@{NSLocalizedDescriptionKey : @"Invalid selected historical cycle"}];
        return nil;
    }
    NSMutableDictionary *result = [record mutableCopy];
    result[@"energy_total"] = NSNull.null;
    result[@"energy_per_hour"] = NSNull.null;
    result[@"energy_coverage_known"] = @NO;
    result[@"energy_partial"] = @YES;
    result[@"energy_error"] = @"Native historical energy is unavailable";
    double start = [record[@"start"] doubleValue], end = [record[@"end"] doubleValue];
    database = database ?: Database();
    NSError *sourceError = nil;
    NSDictionary *source = database ? IEBReadEnergyAndLevels(database, start, end, &sourceError) : nil;
    NSDictionary *energy = nil;
    if (source && !source[@"energy_error"] && [source[@"rows"] isKindOfClass:NSArray.class] &&
        [source[@"rows"] count])
        energy = IEBEnergyForWindow(source[@"rows"], start, end, &sourceError);
    BOOL known = HistoryNumber(source[@"retention_start"]) && HistoryNumber(source[@"retention_end"]) &&
                 [source[@"retention_start"] doubleValue] > 0 && [source[@"retention_end"] doubleValue] > 0 &&
                 [source[@"retention_end"] doubleValue] >= [source[@"retention_start"] doubleValue];
    BOOL partial = !known || [source[@"retention_start"] doubleValue] > start ||
                   [source[@"retention_end"] doubleValue] < end;
    result[@"energy_coverage_known"] = @(known);
    result[@"energy_partial"] = @(partial);
    if (HistoryNumber(energy[@"estimated_native_units"])) {
        double total = [energy[@"estimated_native_units"] doubleValue];
        result[@"energy_total"] = @(total);
        result[@"energy_allocation_estimated"] = @(![energy[@"allocation_exact"] boolValue]);
        double rate = total / ([record[@"duration"] doubleValue] / 3600.0);
        if (!partial && [record[@"power_complete"] isEqual:@YES] && isfinite(rate))
            result[@"energy_per_hour"] = @(rate);
        result[@"energy_error"] =
            partial ? @"Native energy retention does not span the entire saved cycle" : NSNull.null;
    } else {
        result[@"energy_error"]=sourceError.localizedDescription?:source[@"energy_error"]?:@"Native historical energy records have expired or are unavailable";
    }
    // Display evidence is independent of energy availability. Preserve saved activity
    // totals if the native display table has expired or cannot establish initial state.
    NSError *displayError = nil;
    NSDictionary *display = database ? IEBReadDisplayActivity(database, start, end, @[], &displayError) : nil;
    if (display) {
        result[@"screen_on"] = display[@"screen_on"];
        result[@"screen_on_source"] = @"display-events";
    } else
        result[@"display_error"] =
            displayError.localizedDescription ?: @"Native historical display events are unavailable";
    return [result copy];
}
