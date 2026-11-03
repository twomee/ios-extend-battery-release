#import "IEBProbeSupport.h"
#import <math.h>

static NSDictionary *Dictionary(id value) { return [value isKindOfClass:[NSDictionary class]] ? value : @{}; }

static id Count(id value) { return [value isKindOfClass:[NSArray class]] ? @([value count]) : [NSNull null]; }

static id Seconds(id value) {
    if (![value isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return [NSNull null];
    double number = [value doubleValue];
    return isfinite(number) && number >= 0 ? value : [NSNull null];
}

NSDictionary *IEBSummarizeResponse(id response) {
    NSDictionary *root = Dictionary(response);
    NSDictionary *breakdown = Dictionary(root[@"Breakdown"]);
    NSDictionary *total = Dictionary(breakdown[@"PLBatteryUIQueryRangeDayKey"]);
    NSDictionary *graph = Dictionary(Dictionary(root[@"Graph"])[@"PLBatteryUIGraph24hrs"]);
    id levels = graph[@"PLBatteryUIBatteryLevelsKey"];
    NSDictionary *activity = Dictionary(graph[@"PLBatteryUIScreenOnTimeKey"]);
    return @{
        @"response_present" : @(root.count > 0),
        @"app_count" : Count(total[@"PLBatteryUIAppArrayKey"]),
        @"foreground_seconds" : Seconds(total[@"PLBatteryUIForegroundTimeKey"]),
        @"background_seconds" : Seconds(total[@"PLBatteryUIBackgroundTimeKey"]),
        @"hour_count" : Count(breakdown[@"PLBatteryUIQueryRangeDayTapKey"]),
        @"has_level_graph" : @([levels isKindOfClass:[NSArray class]] && [levels count] > 0),
        @"has_activity_graph" : @([activity[@"PLBatteryUIGraphHourly"] isKindOfClass:[NSArray class]] &&
                                  [activity[@"PLBatteryUIGraphHourly"] count] > 0),
    };
}

static BOOL HasReferenceComponents(NSDictionary *summary) {
    return [summary[@"response_present"] isEqual:@YES] &&
           [summary[@"app_count"] isKindOfClass:[NSNumber class]] &&
           [summary[@"app_count"] unsignedIntegerValue] > 0 &&
           [summary[@"hour_count"] isKindOfClass:[NSNumber class]] &&
           [summary[@"hour_count"] unsignedIntegerValue] > 0 &&
           [summary[@"foreground_seconds"] isKindOfClass:[NSNumber class]] &&
           [summary[@"background_seconds"] isKindOfClass:[NSNumber class]] &&
           [summary[@"has_level_graph"] isEqual:@YES] && [summary[@"has_activity_graph"] isEqual:@YES];
}

NSString *IEBFeasibilityDecision(NSDictionary *reference, NSDictionary *scoped) {
    if (!HasReferenceComponents(reference))
        return @"reference-unavailable";
    if (!HasReferenceComponents(scoped))
        return @"missing-scoped-components";
    return @"boundary-validation-required";
}

NSDictionary *IEBParseQueryWindow(NSString *start, NSString *end) {
    NSMutableArray *numbers = [NSMutableArray array];
    for (id text in @[ start ?: (id)[NSNull null], end ?: (id)[NSNull null] ]) {
        if (![text isKindOfClass:[NSString class]] || [text length] == 0 || [text length] > 32)
            return nil;
        NSScanner *scanner = [NSScanner scannerWithString:text];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        scanner.charactersToBeSkipped = nil;
        double value;
        if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value <= 0)
            return nil;
        [numbers addObject:@(value)];
    }
    double span = [numbers[1] doubleValue] - [numbers[0] doubleValue];
    return span > 0 && span <= 864000
               ? @{@"start" : numbers[0],
                   @"end" : numbers[1],
                   @"span" : @(span)}
               : nil;
}
