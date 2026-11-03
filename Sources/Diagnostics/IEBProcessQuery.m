#import "IEBProcessQuery.h"
#import <math.h>
static BOOL Number(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() && isfinite([value doubleValue]) &&
           [value doubleValue] >= 0;
}
static NSString *Name(NSDictionary *row) {
    return [row[@"name"] isKindOfClass:NSString.class] ? row[@"name"] : @"";
}
NSArray *IEBQueryProcesses(NSArray *rows, NSString *query, NSString *sortMode) {
    query = [query isKindOfClass:NSString.class]
                ? [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                : @"";
    BOOL byName = [sortMode isEqual:@"name"];
    NSString *key = [sortMode isEqual:@"energy"]     ? @"energy_percent"
                    : [sortMode isEqual:@"lifetime"] ? @"cpu_seconds"
                                                     : @"cpu_percent";
    NSMutableArray *filtered = [NSMutableArray new];
    for (id raw in rows) {
        if (![raw isKindOfClass:NSDictionary.class])
            continue;
        NSDictionary *row = raw;
        id pid = row[@"pid"];
        if (!Number(pid) || [pid doubleValue] < 1 || [pid doubleValue] != floor([pid doubleValue]))
            continue;
        BOOL match = !query.length ||
                     [Name(row) rangeOfString:query
                                      options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch]
                             .location != NSNotFound ||
                     [[pid stringValue] containsString:query];
        if (match)
            [filtered addObject:row];
    }
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (!byName) {
            BOOL knownA = Number(a[key]), knownB = Number(b[key]);
            if (knownA != knownB)
                return knownA ? NSOrderedAscending : NSOrderedDescending;
            if (knownA && [a[key] doubleValue] != [b[key] doubleValue])
                return [a[key] doubleValue] > [b[key] doubleValue] ? NSOrderedAscending : NSOrderedDescending;
        }
        NSString *nameA = Name(a), *nameB = Name(b);
        if ((nameA.length > 0) != (nameB.length > 0))
            return nameA.length ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult name = [nameA compare:nameB
                                         options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
        return name != NSOrderedSame ? name : [a[@"pid"] compare:b[@"pid"]];
    }];
}
