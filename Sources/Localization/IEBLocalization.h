#import <Foundation/Foundation.h>
@interface IEBLocalizer : NSObject
- (instancetype)initWithBundle:(NSBundle *)bundle;
@property(nonatomic, readonly) NSArray<NSString *> *languages;
- (NSString *)languageForPreferences:(NSArray<NSString *> *)preferences;
- (NSString *)textForKey:(NSString *)key fallback:(NSString *)fallback language:(NSString *)language;
@end
NSArray<NSString *> *IEBAvailableLanguages(void);
NSString *IEBResolvedLanguage(NSArray<NSString *> *preferences);
NSString *IEBCurrentLanguage(void);
BOOL IEBLanguageIsRTL(NSString *language);
NSString *IEBLocalized(NSString *key, NSString *fallback);
NSString *IEBLocalizedInLanguage(NSString *key, NSString *fallback, NSString *language);
