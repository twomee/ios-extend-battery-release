#import "IEBEnergyIntervals.h"
#import <math.h>

static NSNumber *FiniteNumber(id value) {
    return [value isKindOfClass:[NSNumber class]] &&
                   CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
                   isfinite([value doubleValue])
               ? value
               : nil;
}
static id Failure(NSError **error, NSString *message) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBEnergyIntervals"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    return nil;
}
NSDictionary *IEBEnergyForWindow(NSArray *rows, double start, double end, NSError **error) {
    if (error)
        *error = nil;
    if (![rows isKindOfClass:[NSArray class]] || rows.count > 500000 || !isfinite(start) || !isfinite(end) ||
        start <= 0 || end <= start || end - start > 864000)
        return Failure(error, @"Invalid or oversized interval window");
    NSMutableSet *seen = [NSMutableSet set];
    long double estimate = 0, lower = 0, upper = 0;
    NSUInteger overlapping = 0, boundary = 0, nonzero = 0;
    for (id object in rows) {
        if (![object isKindOfClass:[NSDictionary class]])
            return Failure(error, @"Invalid interval row");
        NSDictionary *row = object;
        NSNumber *ID = FiniteNumber(row[@"ID"]), *timestamp = FiniteNumber(row[@"timestamp"]);
        NSNumber *startMS = FiniteNumber(row[@"StartOffset"]), *endMS = FiniteNumber(row[@"EndOffset"]);
        NSNumber *energy = FiniteNumber(row[@"Energy"]), *correction = FiniteNumber(row[@"CorrectionEnergy"]);
        NSNumber *ratio = FiniteNumber(row[@"TerminationRatio"]);
        if (!ID || ID.doubleValue <= 0 || ID.doubleValue != floor(ID.doubleValue) || !timestamp || !startMS ||
            !endMS || !energy || !correction || !ratio || energy.doubleValue < 0 || ratio.doubleValue < 0 ||
            ratio.doubleValue > 100 || [seen containsObject:ID])
            return Failure(error, @"Invalid or duplicate interval record");
        [seen addObject:ID];
        double intervalStart = timestamp.doubleValue + startMS.doubleValue / 1000;
        double intervalEnd = timestamp.doubleValue + endMS.doubleValue / 1000;
        // Reproduce the native getters and aggregate store rounding on 21B91.
        double corrected = energy.doubleValue / 1000 + correction.doubleValue / 1000;
        double attributed = round((ratio.doubleValue / 100) * corrected * 1000);
        if (!isfinite(intervalStart) || !isfinite(intervalEnd) || intervalStart <= 0 ||
            intervalEnd < intervalStart || !isfinite(attributed) || corrected < 0 ||
            (intervalEnd == intervalStart && attributed != 0))
            return Failure(error, @"Invalid interval bounds or corrected energy");
        double overlap = fmin(end, intervalEnd) - fmax(start, intervalStart);
        if (overlap <= 0)
            continue;
        overlapping++;
        if (attributed == 0)
            continue;
        nonzero++;
        BOOL contained = intervalStart >= start && intervalEnd <= end;
        if (contained) {
            estimate += attributed;
            lower += attributed;
        } else {
            estimate += (long double)attributed * (overlap / (intervalEnd - intervalStart));
            boundary++;
        }
        upper += attributed;
    }
    if (!isfinite((double)estimate) || !isfinite((double)lower) || !isfinite((double)upper))
        return Failure(error, @"Energy total exceeds supported range");
    return @{
        @"estimated_native_units" : @((double)estimate),
        @"lower_native_units" : @((double)lower),
        @"upper_native_units" : @((double)upper),
        @"source_record_count" : @(rows.count),
        @"overlapping_interval_count" : @(overlapping),
        @"nonzero_interval_count" : @(nonzero),
        @"boundary_interval_count" : @(boundary),
        @"allocation_exact" : @(boundary == 0)
    };
}
