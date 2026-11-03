#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// Private class declarations (BatteryUsageUI.bundle + Preferences.framework)
// All calls resolve at runtime — nothing is linked against private frameworks.
// Signatures verified against the iOS 17.1.1 (21B91) class dumps.
// ---------------------------------------------------------------------------

@class PSSpecifier;

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
@end

@interface PSSpecifier : NSObject
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSArray *values;
@property (nonatomic, retain) NSDictionary *titleDictionary;
@property (nonatomic) SEL action;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
- (id)propertyForKey:(NSString *)key;
@end

@interface PSSegmentTableCell : UITableViewCell
@end

@interface BatteryUIController : PSListController
@property (nonatomic, retain) NSMutableDictionary *currentDictionary;
@property (nonatomic, retain) NSDictionary *currentLastChargeDictionary;
- (void)queryForBatteryBreakdown;
- (void)setUpBatteryUIDictionary:(NSDictionary *)dict;
@end

@interface PLBatteryUIBackendModel : NSObject
// types: @48@0:8q16@24d32d40
- (void)addQueryType:(long)type withEndDate:(id)endDate withRange:(double)range withBucketSize:(double)bucketSize;
@end

@interface PLBatteryUISegmentCell : PSSegmentTableCell
- (UIFont *)getFittingPreferredFontFromSegment1:(NSString *)s1 andSegment2:(NSString *)s2;
@end

@interface PLBatteryUIBatteryGroupHeader : UIView
// types: v24@0:8@16 — takes one object argument
- (void)setRange:(id)range;
@end
