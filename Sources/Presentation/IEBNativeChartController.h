#import <UIKit/UIKit.h>
@interface IEBNativeChartController : UIViewController
+ (BOOL)isSupported;
+ (CGFloat)heightForTraits:(UITraitCollection *)traits;
- (instancetype)initWithSelection:(void (^)(NSDictionary *range))selection;
@property(nonatomic, copy) NSDictionary *presentation;
- (UITableViewCell *)makeChartCell;
- (BOOL)configureOverview:(NSDictionary *)overview selectedStart:(double)start selectedEnd:(double)end;
@end

// Remember only native chart presentation metadata, never the native usage dataset.
void IEBRememberNativeChartAnchor(UIViewController *chart, NSDate *endOfDay);
void IEBRememberNativeChartLayout(UITableViewCell *cell, UIViewController *chart);
NSDictionary *IEBNativeChartPresentationForTable(UITableView *table);

void IEBRememberNativeChartMargins(UIViewController *chart, double top, double bottom);
void IEBRememberNativeChartBackground(UIViewController *chart, UIColor *color);
