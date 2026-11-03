#import "IEBProcessReaderStatus.h"
#import <math.h>
static id Count(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
                   isfinite([n doubleValue]) && [n doubleValue] >= 0 && [n doubleValue] <= 1000000 &&
                   [n doubleValue] == floor([n doubleValue])
               ? n
               : NSNull.null;
}
NSDictionary *IEBProcessReaderStatus(NSDictionary *snapshot) {
    NSString *provider = [snapshot[@"reader_provider"] isEqual:@"root-service"] ? @"root" : @"limited";
    NSArray *rows = [snapshot[@"rows"] isKindOfClass:NSArray.class] ? snapshot[@"rows"] : nil;
    NSString *state = [@[ @"available", @"partial" ] containsObject:snapshot[@"status"] ?: @""]
                          ? snapshot[@"status"]
                          : @"unavailable";
    NSString *reason = [@[
        @"caller-denied", @"service-unavailable", @"service-timeout", @"untrusted-peer", @"service-failed",
        @"invalid-payload", @"root-collector-unavailable", @"connection-unavailable"
    ] containsObject:snapshot[@"reader_failure"] ?: @""]
                           ? snapshot[@"reader_failure"]
                           : @"unknown";
    return @{
        @"provider" : provider,
        @"state" : state,
        @"readable" : rows ? @(rows.count) : NSNull.null,
        @"denied" : Count(snapshot[@"permission_denied_count"]),
        @"vanished" : Count(snapshot[@"vanished_count"]),
        @"unnamed" : Count(snapshot[@"name_unavailable_count"]),
        @"truncated" : @([snapshot[@"enumeration_truncated"] isEqual:@YES]),
        @"reason" : reason
    };
}
