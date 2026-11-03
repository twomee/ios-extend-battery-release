#import "IEBNativePowerWindow.h"
#import <math.h>
static id Invalid(NSError **error, NSString *reason) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBNativePowerWindow"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : reason}];
    return nil;
}
static BOOL Number(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() && isfinite([value doubleValue]);
}
NSDictionary *IEBNativePowerWindow(NSArray *events, NSError **error) {
    if (error)
        *error = nil;
    if (![events isKindOfClass:NSArray.class] || events.count > 200000)
        return Invalid(error, @"Invalid native power event collection");
    NSString *epoch = nil, *windowEpoch = nil;
    NSMutableSet *epochs = [NSMutableSet new];
    NSInteger power = -1;
    double last = 0, start = 0, end = 0;
    BOOL complete = NO;
    for (id raw in events) {
        if (![raw isKindOfClass:NSDictionary.class] || !Number(raw[@"time"]) ||
            [raw[@"time"] doubleValue] <= 0)
            return Invalid(error, @"Invalid native event date");
        NSDictionary *event = raw;
        double t = [event[@"time"] doubleValue];
        id kind = event[@"kind"];
        if ([kind isEqual:@"epoch"]) {
            id next = event[@"epoch"];
            if (event.count != 3 || ![next isKindOfClass:NSString.class] || ![next length] ||
                [next length] > 128 || [epochs containsObject:next])
                return Invalid(error, @"Invalid or repeated writer epoch");
            if (start && !end) {
                end = MAX(start, last);
                complete = NO;
            }
            epoch = next;
            [epochs addObject:next];
            power = -1;
            last = t;
            continue;
        }
        if (!epoch || t < last)
            return Invalid(error, @"Native power event is out of source order");
        if ([kind isEqual:@"gap"]) {
            if (event.count != 2)
                return Invalid(error, @"Invalid source gap");
            if (start && !end) {
                end = MAX(start, last);
                complete = NO;
            }
            power = -1;
            last = t;
            continue;
        }
        if (![kind isEqual:@"power"] || event.count != 3 || !Number(event[@"power"]))
            return Invalid(error, @"Invalid native power event");
        double value = [event[@"power"] doubleValue];
        if (value != 0 && value != 1)
            return Invalid(error, @"Invalid external power value");
        NSInteger next = (NSInteger)value;
        if (t == last && power != -1 && next != power)
            return Invalid(error, @"Conflicting power edges at one timestamp");
        if (power == 1 && next == 0) {
            start = t;
            end = 0;
            complete = YES;
            windowEpoch = epoch;
        } else if (next == 1 && start && !end)
            end = t;
        power = next;
        last = t;
    }
    NSMutableDictionary *result = [@{@"power" : @(power), @"power_complete" : @(complete)} mutableCopy];
    if (epoch) {
        result[@"current_epoch"] = epoch;
        result[@"last_native_time"] = @(last);
    }
    if (start) {
        result[@"start"] = @(start);
        result[@"epoch"] = windowEpoch;
    }
    if (end)
        result[@"end"] = @(end);
    return [result copy];
}
