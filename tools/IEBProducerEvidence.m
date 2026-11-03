#import "IEBProducerEvidence.h"
#import <math.h>

static NSDictionary *AsDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSNumber *FiniteNumber(id value) {
    if (![value isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || !isfinite([value doubleValue]))
        return nil;
    return value;
}

static NSString *ResponseName(NSDictionary *request) {
    NSNumber *version = FiniteNumber(request[@"IEBProbeVersion"]);
    NSNumber *type = FiniteNumber(request[@"enum"]);
    NSNumber *start = FiniteNumber(request[@"start"]);
    NSNumber *end = FiniteNumber(request[@"end"]);
    NSNumber *bucket = FiniteNumber(request[@"bucket"]);
    if (![version isEqual:@1] || !type || !start || !end || !bucket || start.doubleValue <= 0 ||
        end.doubleValue <= start.doubleValue || end.doubleValue - start.doubleValue > 864000 ||
        bucket.doubleValue <= 0 || bucket.doubleValue > 864000 || type.doubleValue != floor(type.doubleValue))
        return nil;
    return @{
        @0 : @"ChargingIntervals",
        @1 : @"BatteryBreakdown",
        @5 : @"LastChargeLevel",
        @7 : @"UISOCLevel",
        @8 : @"UsageTimes"
    }[type];
}

// Matches PLBatteryUsageUIKeyFromConfiguration on build 21B91. Unlike the
// client payload key, this key excludes the response type (already the parent).
static NSString *ProducerConfigurationKey(NSDictionary *request) {
    double span = [request[@"end"] doubleValue] - [request[@"start"] doubleValue];
    double bucket = [request[@"bucket"] doubleValue];
    NSString *range = span == 864000   ? @"10d"
                      : span == 604800 ? @"7d"
                      : span == 86400  ? @"24hr"
                      : span == 3600   ? @"1hr"
                                       : @"UnknownRange";
    return span / bucket == 1 ? range : [NSString stringWithFormat:@"%@_%zu", range, (size_t)bucket];
}

BOOL IEBIsProducerProbe(id configuration) {
    NSDictionary *requests = AsDictionary(configuration);
    if (requests.count > 64 || ![requests[@"skipPlistWriteKey"] isKindOfClass:[NSNumber class]] ||
        ![requests[@"skipPlistWriteKey"] isEqual:@1])
        return NO;
    for (id key in requests) {
        if ([key isKindOfClass:[NSString class]] && [key length] <= 256 &&
            ResponseName(AsDictionary(requests[key])))
            return YES;
    }
    return NO;
}

NSDictionary *IEBProducerEvidence(id rawResponse, id configuration) {
    NSDictionary *raw = AsDictionary(rawResponse);
    NSDictionary *requests = AsDictionary(configuration);
    NSMutableArray *observations = [NSMutableArray array];
    if (requests.count > 64)
        return @{@"schema_version" : @1, @"requests" : observations, @"limited" : @YES};
    if (!IEBIsProducerProbe(configuration))
        return @{@"schema_version" : @1, @"requests" : observations, @"limited" : @NO};
    for (id key in requests) {
        if (![key isKindOfClass:[NSString class]] || [key length] > 256)
            continue;
        NSDictionary *request = AsDictionary(requests[key]);
        NSString *name = ResponseName(request);
        if (!name)
            continue;
        NSDictionary *group = AsDictionary(raw[name]);
        id result = group[@"result"] ?: AsDictionary(group[ProducerConfigurationKey(request)])[@"result"];
        NSMutableDictionary *row = [@{
            @"response_type" : request[@"enum"],
            @"requested_start" : request[@"start"],
            @"requested_end" : request[@"end"],
            @"requested_bucket_seconds" : request[@"bucket"],
            @"result_present" : @(result != nil && result != [NSNull null]),
            @"truncated" : @NO,
        } mutableCopy];
        id buckets = AsDictionary(result)[@"PLBatteryUIBreakdownKey"];
        if ([buckets isKindOfClass:[NSArray class]]) {
            NSUInteger appEntries = 0, outside = 0, missing = 0;
            BOOL validCounts = YES;
            double earliest = INFINITY, latest = -INFINITY;
            NSUInteger limit = MIN([buckets count], (NSUInteger)512);
            for (NSUInteger i = 0; i < limit; i++) {
                NSDictionary *bucket = AsDictionary(buckets[i]);
                NSNumber *start = FiniteNumber(bucket[@"PLBatteryUIBucketStartKey"]);
                NSNumber *end = FiniteNumber(bucket[@"PLBatteryUIBucketEndKey"]);
                if (!start || !end || end.doubleValue < start.doubleValue)
                    missing++;
                else {
                    earliest = fmin(earliest, start.doubleValue);
                    latest = fmax(latest, end.doubleValue);
                    if (start.doubleValue < [request[@"start"] doubleValue] ||
                        end.doubleValue > [request[@"end"] doubleValue])
                        outside++;
                }
                id apps = bucket[@"PLBatteryUIAppArrayKey"];
                if (![apps isKindOfClass:[NSArray class]] || NSUIntegerMax - appEntries < [apps count])
                    validCounts = NO;
                else
                    appEntries += [apps count];
            }
            row[@"bucket_count"] = @([buckets count]);
            if (validCounts && limit == [buckets count])
                row[@"app_entry_count"] = @(appEntries);
            row[@"outside_bucket_count"] = @(outside);
            row[@"missing_boundary_count"] = @(missing);
            row[@"truncated"] = @(limit < [buckets count]);
            if (missing == 0 && limit == [buckets count] && isfinite(earliest) && isfinite(latest)) {
                row[@"earliest_bucket_start"] = @(earliest);
                row[@"latest_bucket_end"] = @(latest);
            }
        }
        // Array-valued responses expose only their cardinality, never values.
        if ([result isKindOfClass:[NSArray class]])
            row[@"sample_count"] = @([result count]);
        id graphBuckets = AsDictionary(result)[@"PLBatteryUIGraphByBucket"];
        if ([graphBuckets isKindOfClass:[NSDictionary class]] || [graphBuckets isKindOfClass:[NSArray class]])
            row[@"graph_bucket_count"] = @([graphBuckets count]);
        if ([request[@"enum"] isEqual:@8]) {
            for (NSString *kind in @[ @"on", @"off" ]) {
                NSString *nativeKey =
                    [kind isEqual:@"on"] ? @"PLBatteryUIScreenOnTimeKey" : @"PLBatteryUIScreenOffTimeKey";
                NSDictionary *screen = AsDictionary(AsDictionary(result)[nativeKey]);
                id samples = screen[@"PLBatteryUIGraphByBucket"];
                if ([samples isKindOfClass:[NSArray class]])
                    row[[NSString stringWithFormat:@"screen_%@_bucket_count", kind]] = @([samples count]);
                NSNumber *total = FiniteNumber(screen[@"PLBatteryUIGraphTotal"]);
                if (total && total.doubleValue >= 0)
                    row[[NSString stringWithFormat:@"screen_%@_seconds", kind]] = total;
            }
        }
        [observations addObject:row];
    }
    return @{@"schema_version" : @1, @"requests" : observations, @"limited" : @NO};
}
NSDictionary *IEBSanitizeProducerEvidence(id evidence) {
    NSDictionary *source = AsDictionary(evidence);
    id requests = source[@"requests"];
    if (![FiniteNumber(source[@"schema_version"]) isEqual:@1] || ![requests isKindOfClass:[NSArray class]] ||
        [requests count] > 64)
        return @{@"available" : @NO};
    NSArray *numericKeys = @[
        @"response_type", @"requested_start", @"requested_end", @"requested_bucket_seconds", @"bucket_count",
        @"app_entry_count", @"outside_bucket_count", @"missing_boundary_count", @"sample_count",
        @"graph_bucket_count", @"earliest_bucket_start", @"latest_bucket_end", @"screen_on_bucket_count",
        @"screen_off_bucket_count", @"screen_on_seconds", @"screen_off_seconds"
    ];
    NSMutableArray *rows = [NSMutableArray array];
    for (id object in requests) {
        NSDictionary *row = AsDictionary(object);
        NSMutableDictionary *safe = [NSMutableDictionary dictionary];
        for (NSString *key in numericKeys) {
            NSNumber *number = FiniteNumber(row[key]);
            safe[key] = number && number.doubleValue >= 0 ? number : (id)[NSNull null];
        }
        for (NSString *key in @[ @"result_present", @"truncated" ]) {
            id value = row[key];
            safe[key] = [value isEqual:@YES] ? @YES : [value isEqual:@NO] ? @NO : (id)[NSNull null];
        }
        [rows addObject:safe];
    }
    return @{
        @"available" : @YES,
        @"schema_version" : @1,
        @"requests" : rows,
        @"limited" : @([source[@"limited"] isEqual:@YES])
    };
}
