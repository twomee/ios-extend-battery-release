#import "IEBProcessAttribution.h"
#import "IEBProcessSnapshot.h"
#import <math.h>
NSDictionary *IEBProcessAttribution(NSArray *sources, NSDictionary *catalog, NSDictionary *snapshot,
                                    NSDictionary *previous) {
    NSMutableDictionary *aliases = [NSMutableDictionary new], *names = [NSMutableDictionary new],
                        *old = [NSMutableDictionary new], *matched = [NSMutableDictionary new];
    for (NSDictionary *source in sources) {
        NSString *identity = source[@"id"], *executable = catalog[identity][@"executable"];
        if (![identity isKindOfClass:NSString.class] || !identity.length)
            continue;
        if ([executable isKindOfClass:NSString.class] && executable.length &&
            ![catalog[identity][@"executable_unique"] isEqual:@YES])
            continue;
        NSString *name =
            [executable isKindOfClass:NSString.class] && executable.length ? executable : identity;
        if (!aliases[name])
            aliases[name] = [NSMutableArray new];
        [aliases[name] addObject:source];
    }
    for (NSDictionary *row in snapshot[@"rows"]) {
        NSString *name = row[@"name"];
        if (![name isKindOfClass:NSString.class] || !name.length)
            continue;
        if (!names[name])
            names[name] = [NSMutableArray new];
        [names[name] addObject:row];
    }
    for (NSDictionary *row in previous[@"rows"])
        if (row[@"pid"])
            old[row[@"pid"]] = row;
    // Unreadable or unenumerated instances can invalidate an apparently unique process name.
    BOOL complete =
        [snapshot[@"status"] isEqual:@"available"] && [snapshot[@"enumeration_truncated"] isEqual:@NO] &&
        [snapshot[@"unavailable_count"] isEqual:@0] && [snapshot[@"name_unavailable_count"] isEqual:@0] &&
        [snapshot[@"enumerated_count"] isKindOfClass:NSNumber.class] &&
        [snapshot[@"enumerated_count"] unsignedIntegerValue] == [snapshot[@"rows"] count];
    NSMutableArray *processes = [NSMutableArray new];
    for (NSDictionary *row in snapshot[@"rows"]) {
        NSMutableDictionary *copy = [row mutableCopy];
        NSDictionary *delta = IEBProcessCPUDelta(old[row[@"pid"]], row);
        copy[@"cpu_percent"] = delta[@"cpu_percent"] ?: NSNull.null;
        copy[@"cpu_window"] = delta[@"window_seconds"] ?: NSNull.null;
        NSString *name = row[@"name"];
        NSArray *candidates = aliases[name];
        BOOL unique = complete && [names[name] count] == 1 && candidates.count == 1;
        NSDictionary *source = unique ? candidates[0] : nil;
        id percent = source[@"percent"];
        copy[@"energy_percent"] = [percent isKindOfClass:NSNumber.class] && isfinite([percent doubleValue]) &&
                                          [percent doubleValue] >= 0 && [percent doubleValue] <= 100
                                      ? percent
                                      : NSNull.null;
        if (source) {
            copy[@"energy_source"] = source[@"id"];
            matched[source[@"id"]] = copy;
        }
        [processes addObject:copy];
    }
    return @{@"sources" : matched, @"processes" : processes};
}
