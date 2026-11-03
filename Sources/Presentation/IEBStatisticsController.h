#import "../Localization/IEBLocalization.h"
#import <UIKit/UIKit.h>
@interface IEBStatisticsController : UITableViewController
@property(nonatomic) BOOL nativeTablePresentation;
@property(nonatomic, copy) void (^nativePresentationDidUpdate)(void);
- (UIView *)nativeChartView;
- (void)beginNativeTablePresentationInOwner:(UIViewController *)owner;
- (void)endNativeTablePresentation;
- (void)updateNativeTimeUsageCell:(UITableViewCell *)cell;
@property(nonatomic, copy) NSDictionary *nativeChartPresentation;
@property(nonatomic, copy) NSDictionary * (^nativeChartPresentationProvider)(void);
- (instancetype)initWithLoader:(NSDictionary * (^)(double start, double end, NSError **error))loader;
- (instancetype)initWithLoader:(NSDictionary * (^)(double start, double end, NSError **error))loader
               catalogProvider:(NSDictionary * (^)(NSArray<NSString *> *identities))provider;
@end
