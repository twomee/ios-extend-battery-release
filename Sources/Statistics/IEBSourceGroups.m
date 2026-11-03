#import "IEBSourceGroups.h"
BOOL IEBIsUserFacingApplication(NSDictionary *info) {
    if (![info isKindOfClass:NSDictionary.class])
        return NO;
    id tags = info[@"SBAppTags"];
    if (tags && ![tags isKindOfClass:NSArray.class])
        return NO;
    if ([tags containsObject:@"hidden"])
        return NO;
    for (NSString *key in @[ @"LSUIElement", @"LSBackgroundOnly" ]) {
        id flag = info[key];
        if (flag && (![flag isKindOfClass:NSNumber.class] || [flag boolValue]))
            return NO;
    }
    id visible = info[@"SBIconVisibilityDefaultVisible"];
    if (visible && (![visible isKindOfClass:NSNumber.class] || ![visible boolValue]))
        return NO;
    return YES;
}
NSDictionary *IEBSourceGroups(NSArray<NSDictionary *> *rows, NSDictionary *catalog) {
    NSMutableArray *applications = [NSMutableArray new], *processes = [NSMutableArray new];
    for (NSDictionary *row in rows) {
        id metadata = catalog[row[@"id"]];
        BOOL app = [metadata isKindOfClass:NSDictionary.class] &&
                   [metadata[@"name"] isKindOfClass:NSString.class] && [metadata[@"name"] length] > 0 &&
                   [metadata[@"user_facing"] isKindOfClass:NSNumber.class] &&
                   [metadata[@"user_facing"] boolValue];
        [(app ? applications : processes) addObject:row];
    }
    return @{@"applications" : applications, @"system_processes" : processes};
}
