#import "IEBLocalization.h"
static NSString *LanguageCode(id input) {
    if (![input isKindOfClass:NSString.class] || ![input length])
        return nil;
    NSString *code = [input stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    if ([code rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound)
        return nil;
    NSArray *parts = [code componentsSeparatedByString:@"-"];
    if ([parts containsObject:@""] || [parts.firstObject length] < 2)
        return nil;
    if ([[parts.firstObject lowercaseString] isEqual:@"iw"]) {
        NSMutableArray *alias = [parts mutableCopy];
        alias[0] = @"he";
        code = [alias componentsJoinedByString:@"-"];
    }
    return [NSLocale canonicalLanguageIdentifierFromString:code];
}
@implementation IEBLocalizer {
    NSDictionary<NSString *, NSDictionary *> *_tables;
}
- (instancetype)initWithBundle:(NSBundle *)bundle {
    self = [super init];
    if (!self)
        return nil;
    NSMutableDictionary *tables = [NSMutableDictionary dictionary];
    for (NSString *language in bundle.localizations) {
        if (!LanguageCode(language) || [language isEqual:@"Base"])
            continue;
        NSString *file =
            [[bundle.bundlePath stringByAppendingPathComponent:[language stringByAppendingString:@".lproj"]]
                stringByAppendingPathComponent:@"Localizable.strings"];
        NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:file];
        if (![values isKindOfClass:NSDictionary.class])
            continue;
        NSMutableDictionary *valid = [NSMutableDictionary dictionary];
        for (id key in values) {
            id value = values[key];
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class] && [value length])
                valid[key] = value;
        }
        tables[language] = [valid copy];
    }
    _tables = [tables copy];
    return self;
}
- (NSArray<NSString *> *)languages {
    return [_tables.allKeys sortedArrayUsingSelector:@selector(compare:)];
}
- (NSString *)languageForPreferences:(NSArray<NSString *> *)preferences {
    NSMutableArray *valid = [NSMutableArray array];
    for (id value in preferences) {
        NSString *code = LanguageCode(value);
        if (code)
            [valid addObject:code];
    }
    [valid addObject:@"en"];
    NSString *chosen =
        [NSBundle preferredLocalizationsFromArray:self.languages forPreferences:valid].firstObject;
    return chosen && _tables[chosen] ? chosen : @"en";
}
- (NSString *)textForKey:(NSString *)key fallback:(NSString *)fallback language:(NSString *)language {
    NSString *chosen = [self languageForPreferences:language ? @[ language ] : NSLocale.preferredLanguages];
    return _tables[chosen][key] ?: _tables[@"en"][key] ?: fallback ?: key;
}
@end
static IEBLocalizer *SharedLocalizer(void) {
    static IEBLocalizer *localizer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = @[
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"IEBLocalizations.bundle"],
            @"/var/jb/Library/Application Support/iOSExtendBattery/IEBLocalizations.bundle",
            @"/Library/Application Support/iOSExtendBattery/IEBLocalizations.bundle"
        ];
        NSBundle *bundle = nil;
        for (NSString *path in paths) {
            NSBundle *candidate = [NSBundle bundleWithPath:path];
            if (candidate.localizations.count) {
                bundle = candidate;
                break;
            }
        }
        localizer = [[IEBLocalizer alloc] initWithBundle:bundle];
        if (!bundle)
            NSLog(@"IEB localization resources unavailable; using English defaults.");
    });
    return localizer;
}
NSArray<NSString *> *IEBAvailableLanguages(void) { return SharedLocalizer().languages; }
NSString *IEBResolvedLanguage(NSArray<NSString *> *preferences) {
    return [SharedLocalizer() languageForPreferences:preferences];
}
NSString *IEBCurrentLanguage(void) { return IEBResolvedLanguage(NSLocale.preferredLanguages); }
BOOL IEBLanguageIsRTL(NSString *language) {
    NSString *code = LanguageCode(language);
    return code && [NSLocale characterDirectionForLanguage:code] == NSLocaleLanguageDirectionRightToLeft;
}
NSString *IEBLocalizedInLanguage(NSString *key, NSString *fallback, NSString *language) {
    return [SharedLocalizer() textForKey:key fallback:fallback language:language];
}
NSString *IEBLocalized(NSString *key, NSString *fallback) {
    return IEBLocalizedInLanguage(key, fallback, nil);
}
