#import "../Sources/Localization/IEBLocalization.h"
#define C(...)                                                                                               \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Localization FAIL line %d: %s\n", __LINE__, #__VA_ARGS__);                      \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"IEBLocalizer");
        C(cls != Nil);
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *path = [folder stringByAppendingPathComponent:@"Fixture.bundle"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSArray *languages = @[ @"en", @"he", @"fr", @"ar", @"pt-BR", @"zh-Hans", @"zh-Hant" ];
        for (NSString *language in languages) {
            NSString *dir =
                [path stringByAppendingPathComponent:[language stringByAppendingString:@".lproj"]];
            C([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
            NSDictionary *strings = [language isEqual:@"fr"] ? @{@"greeting" : @"Bonjour"}
                                    : [language isEqual:@"he"]
                                        ? @{@"greeting" : @"שלום"}
                                        : @{@"greeting" : @"Hello", @"only_english" : @"English fallback"};
            C([strings writeToFile:[dir stringByAppendingPathComponent:@"Localizable.strings"]
                        atomically:YES]);
        }
        C([@{
            @"CFBundleIdentifier" : @"test.ieb.localizations",
            @"CFBundleDevelopmentRegion" : @"en",
            @"CFBundleLocalizations" : languages
        } writeToFile:[path stringByAppendingPathComponent:@"Info.plist"]
            atomically:YES]);
        IEBLocalizer *localizer = [[cls alloc] initWithBundle:[NSBundle bundleWithPath:path]];
        C([localizer.languages containsObject:@"he"]);
        C([[localizer languageForPreferences:@[ @"fr-CA", @"he" ]] isEqual:@"fr"]);
        C([[localizer languageForPreferences:@[ @"xx", @"HE_il" ]] isEqual:@"he"]);
        C([[localizer languageForPreferences:@[ @"iw-IL" ]] isEqual:@"he"]);
        C([[localizer languageForPreferences:@[ @"zh-TW" ]] isEqual:@"zh-Hant"]);
        C([[localizer languageForPreferences:@[ @"zh-CN" ]] isEqual:@"zh-Hans"]);
        C([[localizer languageForPreferences:@[ @"pt-BR" ]] isEqual:@"pt-BR"]);
        C([[localizer languageForPreferences:@[ @"../../he", @"xx" ]] isEqual:@"en"]);
        C([[localizer languageForPreferences:@[]] isEqual:@"en"]);
        C([[localizer textForKey:@"greeting" fallback:@"Hello" language:@"fr-CA"] isEqual:@"Bonjour"]);
        C([[localizer textForKey:@"greeting" fallback:@"Hello" language:@"iw"] isEqual:@"שלום"]);
        C([[localizer textForKey:@"only_english" fallback:@"Inline fallback"
                        language:@"fr"] isEqual:@"English fallback"]);
        C([[localizer textForKey:@"missing" fallback:@"Inline fallback"
                        language:@"fr"] isEqual:@"Inline fallback"]);
        C([[localizer textForKey:@"greeting" fallback:@"Hello" language:@"../../he"] isEqual:@"Hello"]);
        IEBLocalizer *missing = [[cls alloc] initWithBundle:nil];
        C([[missing languageForPreferences:@[ @"fr" ]] isEqual:@"en"]);
        C([[missing textForKey:@"title" fallback:@"Since Unplugged"
                      language:@"fr"] isEqual:@"Since Unplugged"]);
        C([fm removeItemAtPath:folder error:nil]);
        C([IEBAvailableLanguages() containsObject:@"fr"]);
        C([IEBAvailableLanguages() containsObject:IEBCurrentLanguage()]);
        C([IEBResolvedLanguage(@[ @"fr-CA" ]) isEqual:@"fr"]);
        NSString *frenchPath = [NSBundle.mainBundle.bundlePath
            stringByAppendingPathComponent:@"IEBLocalizations.bundle/fr.lproj/Localizable.strings"];
        NSString *frenchTitle = [NSDictionary dictionaryWithContentsOfFile:frenchPath][@"SINCE_UNPLUGGED"];
        C(frenchTitle.length &&
          [IEBLocalizedInLanguage(@"SINCE_UNPLUGGED", @"Since Unplugged", @"fr") isEqual:frenchTitle]);
        C([IEBLocalizedInLanguage(@"MISSING_TEST_KEY", @"Safe English", @"ar") isEqual:@"Safe English"]);
        C([IEBLocalized(@"MISSING_TEST_KEY", @"Safe English") isEqual:@"Safe English"]);
        C(IEBLanguageIsRTL(@"ar") && IEBLanguageIsRTL(@"he-IL") && IEBLanguageIsRTL(@"iw"));
        C(!IEBLanguageIsRTL(@"en") && !IEBLanguageIsRTL(@"fr") && !IEBLanguageIsRTL(@"../../he"));
        puts("PASS real bundle language precedence, aliases, scripts, key fallback and missing resources");
    }
    return 0;
}
