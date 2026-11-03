#import "IEBCompatibilityEvidence.h"
#import <objc/runtime.h>
static BOOL IsBooleanNumber(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
NSDictionary *IEBCompatibilitySummary(id observations, NSUInteger expectedCount, BOOL imagesLoaded) {
    NSDictionary *invalid = @{@"status" : @"invalid"};
    if (![observations isKindOfClass:NSArray.class] || !expectedCount || [observations count] > expectedCount)
        return invalid;
    NSMutableSet *identities = [NSMutableSet new];
    NSUInteger matched = 0, missing = 0, mismatched = 0;
    for (id row in observations) {
        if (![row isKindOfClass:NSDictionary.class])
            return invalid;
        id identity = row[@"id"], cls = row[@"class_present"], member = row[@"member_present"],
           matches = row[@"matches_expected"];
        if (![identity isKindOfClass:NSString.class] || ![identity length] ||
            [identities containsObject:identity] || !IsBooleanNumber(cls) || !IsBooleanNumber(member) ||
            !IsBooleanNumber(matches))
            return invalid;
        if ((![cls boolValue] && [member boolValue]) ||
            ([matches boolValue] && (![cls boolValue] || ![member boolValue])))
            return invalid;
        [identities addObject:identity];
        if (![cls boolValue] || ![member boolValue])
            missing++;
        else if (![matches boolValue])
            mismatched++;
        else
            matched++;
    }
    NSString *status = [observations count] < expectedCount ? @"incomplete"
                       : !imagesLoaded || missing           ? @"unavailable"
                       : mismatched                         ? @"abi_mismatch"
                                                            : @"metadata_match_only";
    return @{
        @"status" : status,
        @"matched" : @(matched),
        @"missing" : @(missing),
        @"mismatched" : @(mismatched),
        @"expected" : @(expectedCount),
        @"observed" : @([observations count])
    };
}

static NSString *Owner(Class cls, SEL selector, BOOL meta) {
    Class cursor = meta ? object_getClass(cls) : cls;
    for (NSUInteger depth = 0; cursor && depth < 128; depth++, cursor = class_getSuperclass(cursor)) {
        unsigned count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        BOOL found = NO;
        for (unsigned i = 0; i < count; i++) {
            if (sel_isEqual(method_getName(methods[i]), selector)) {
                found = YES;
                break;
            }
        }
        free(methods);
        if (found)
            return NSStringFromClass(cursor);
    }
    return nil;
}
NSDictionary *IEBInspectCompatibilityMember(NSArray<NSString *> *spec) {
    NSString *kind = spec[0], *name = spec[1], *member = spec[2], *expected = spec[3];
    Class cls = NSClassFromString(name);
    BOOL present = NO, matches = NO;
    const char *encoding = NULL;
    NSString *owner = nil;
    if ([kind isEqual:@"ivar"]) {
        Ivar ivar = cls ? class_getInstanceVariable(cls, member.UTF8String) : NULL;
        present = ivar != NULL;
        matches = present;
        encoding = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    } else {
        SEL sel = NSSelectorFromString(member);
        BOOL meta = [kind isEqual:@"class_method"];
        Method method =
            cls ? (meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel)) : NULL;
        present = method != NULL;
        encoding = method ? method_getTypeEncoding(method) : NULL;
        matches = encoding && [expected isEqual:@(encoding)];
        owner = Owner(cls, sel, meta);
    }
    const char *image = cls ? class_getImageName(cls) : NULL;
    return @{
        @"id" : [NSString stringWithFormat:@"%@/%@/%@", kind, name, member],
        @"class_present" : @((BOOL)(cls != Nil)),
        @"member_present" : @(present),
        @"matches_expected" : @(matches),
        @"expected" : expected,
        @"encoding" : encoding ? @(encoding) : (id)NSNull.null,
        @"declared_by" : owner ?: (id)NSNull.null,
        @"class_image" : image ? [@(image) lastPathComponent] : (id)NSNull.null
    };
}
