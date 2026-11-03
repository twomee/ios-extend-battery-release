#import "IEBNativeChartController.h"
#import "../Statistics/IEBNativeChartData.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
static Class NativeClass(void) {
    return NSClassFromString(@"_TtC14BatteryUsageUI24PLBUIChartViewController");
}
static BOOL MethodABI(Class cls, NSString *name, BOOL meta, const char *encoding) {
    Method m = meta ? class_getClassMethod(cls, NSSelectorFromString(name))
                    : class_getInstanceMethod(cls, NSSelectorFromString(name));
    return m && strcmp(method_getTypeEncoding(m), encoding) == 0;
}
static void Send(id target, NSString *name, id arg) {
    ((void (*)(id, SEL, id))objc_msgSend)(target, NSSelectorFromString(name), arg);
}
static const void *OwnedChartKey = &OwnedChartKey;
static const void *NativeAnchorKey = &NativeAnchorKey;
static const void *NativePresentationKey = &NativePresentationKey;
static const void *NativeMarginsKey = &NativeMarginsKey;
static const void *NativeBackgroundKey = &NativeBackgroundKey;
void IEBRememberNativeChartMargins(UIViewController *chart, double top, double bottom) {
    if (!chart || objc_getAssociatedObject(chart, OwnedChartKey) || !isfinite(top) || !isfinite(bottom) ||
        top < 0 || bottom < 0 || top > 1200 || bottom > 1200)
        return;
    objc_setAssociatedObject(
        chart, NativeMarginsKey,
        @{@"top_margin" : @(top),
          @"bottom_margin" : @(bottom)},
        OBJC_ASSOCIATION_COPY_NONATOMIC);
}
void IEBRememberNativeChartBackground(UIViewController *chart, UIColor *color) {
    if (chart && !objc_getAssociatedObject(chart, OwnedChartKey) && [color isKindOfClass:UIColor.class])
        objc_setAssociatedObject(chart, NativeBackgroundKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static UITableView *ContainingTable(UIView *view) {
    while (view && ![view isKindOfClass:UITableView.class])
        view = view.superview;
    return (UITableView *)view;
}
void IEBRememberNativeChartLayout(UITableViewCell *cell, UIViewController *chart) {
    if (!cell || !chart || objc_getAssociatedObject(chart, OwnedChartKey) || !chart.isViewLoaded)
        return;
    UITableView *table = ContainingTable(cell);
    NSDate *anchor = objc_getAssociatedObject(chart, NativeAnchorKey);
    if (!table || !anchor || table.bounds.size.width <= 0 || ![chart.view isDescendantOfView:cell])
        return;
    CGRect rect = [chart.view convertRect:chart.view.bounds toView:table];
    CGFloat left = rect.origin.x - table.bounds.origin.x;
    CGFloat right = table.bounds.size.width - left - rect.size.width;
    if (!isfinite(left) || !isfinite(right) || left < 0 || right < -0.5 || rect.size.width <= 0 ||
        rect.size.height < 200 || rect.size.height > 1200)
        return;
    NSMutableDictionary *presentation = [@{
        @"end_of_day" : anchor,
        @"left" : @(left),
        @"right" : @(MAX(0, right)),
        @"height" : @(rect.size.height)
    } mutableCopy];
    NSDictionary *margins = objc_getAssociatedObject(chart, NativeMarginsKey);
    if (margins)
        [presentation addEntriesFromDictionary:margins];
    UIColor *background = objc_getAssociatedObject(chart, NativeBackgroundKey);
    if (background)
        presentation[@"background"] = background;
    objc_setAssociatedObject(table, NativePresentationKey, presentation, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
void IEBRememberNativeChartAnchor(UIViewController *chart, NSDate *endOfDay) {
    if (!chart || objc_getAssociatedObject(chart, OwnedChartKey) || ![endOfDay isKindOfClass:NSDate.class] ||
        !isfinite(endOfDay.timeIntervalSince1970) || endOfDay.timeIntervalSince1970 <= 86400)
        return;
    objc_setAssociatedObject(chart, NativeAnchorKey, endOfDay, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIView *cell = chart.isViewLoaded ? chart.view.superview : nil;
    while (cell && ![cell isKindOfClass:UITableViewCell.class])
        cell = cell.superview;
    if (cell)
        IEBRememberNativeChartLayout((UITableViewCell *)cell, chart);
}
NSDictionary *IEBNativeChartPresentationForTable(UITableView *table) {
    return objc_getAssociatedObject(table, NativePresentationKey);
}
@interface IEBNativeChartCell : UITableViewCell
@property(nonatomic, strong) UIView *chartView;
@property(nonatomic, copy) NSDictionary *presentation;
@end
@implementation IEBNativeChartCell
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event] ||
           [self.chartView pointInside:[self.chartView convertPoint:point fromView:self] withEvent:event];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled)
        return nil;
    UIView *chartHit = [self.chartView hitTest:[self.chartView convertPoint:point fromView:self]
                                     withEvent:event];
    return chartHit ?: [super hitTest:point withEvent:event];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UITableView *table = ContainingTable(self);
    if (!table || !self.presentation) {
        self.chartView.frame = self.contentView.bounds;
        return;
    }
    CGFloat left = [self.presentation[@"left"] doubleValue];
    CGFloat right = [self.presentation[@"right"] doubleValue];
    CGFloat width = table.bounds.size.width - left - right;
    if (width <= 0)
        return;
    CGPoint origin = [self.contentView convertPoint:CGPointMake(table.bounds.origin.x + left, 0)
                                           fromView:table];
    self.chartView.frame = CGRectMake(origin.x, 0, width, self.contentView.bounds.size.height);
}
@end
@interface IEBNativeChartController ()
@property(nonatomic, strong) UIViewController *chart;
@property(nonatomic, copy) NSDictionary *data;
@property(nonatomic, copy) void (^selection)(NSDictionary *range);
@property(nonatomic) BOOL configuring;
@end
@implementation IEBNativeChartController
+ (BOOL)isSupported {
    Class c = NativeClass();
    return c && [c isSubclassOfClass:UIViewController.class] &&
           MethodABI(c, @"setDataset:endOfDay:", NO, "v32@0:8@16@24") &&
           MethodABI(c, @"setTappedIndex:", NO, "v24@0:8@16") &&
           MethodABI(c, @"setActiveChart:", NO, "v24@0:8@16") &&
           MethodABI(c, @"setDelegate:", NO, "v24@0:8@16") && MethodABI(c, @"beginUpdate", NO, "v16@0:8") &&
           MethodABI(c, @"endUpdate", NO, "v16@0:8") &&
           MethodABI(c, @"chartIdentifier24Hrs", YES, "@16@0:8") &&
           MethodABI(c, @"graphHeightWithTraitCollection:", YES, "d24@0:8@16");
}
+ (CGFloat)heightForTraits:(UITraitCollection *)traits {
    if (![self isSupported])
        return 400;
    double height = ((double (*)(id, SEL, id))objc_msgSend)(
        NativeClass(), NSSelectorFromString(@"graphHeightWithTraitCollection:"), traits);
    return isfinite(height) && height >= 200 && height <= 1200 ? height : 400;
}
- (instancetype)initWithSelection:(void (^)(NSDictionary *))selection {
    if (![self.class isSupported])
        return nil;
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _selection = [selection copy];
        _chart = [[NativeClass() alloc] initWithNibName:nil bundle:nil];
        objc_setAssociatedObject(_chart, OwnedChartKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Send(_chart, @"setDelegate:", self);
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.view.userInteractionEnabled = NO;
    [self addChildViewController:self.chart];
    self.chart.view.frame = self.view.bounds;
    self.chart.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.chart.view];
    [self.chart didMoveToParentViewController:self];
}
- (UITableViewCell *)makeChartCell {
    IEBNativeChartCell *cell = [[IEBNativeChartCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                         reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = UIColor.clearColor;
    cell.clipsToBounds = NO;
    cell.contentView.clipsToBounds = NO;
    cell.presentation = self.presentation;
    cell.chartView = self.view;
    [cell.contentView addSubview:self.view];
    return cell;
}
- (BOOL)configureOverview:(NSDictionary *)overview selectedStart:(double)start selectedEnd:(double)end {
    NSError *error = nil;
    NSMutableDictionary *input = [overview mutableCopy];
    NSDate *anchor = self.presentation[@"end_of_day"];
    if ([anchor isKindOfClass:NSDate.class])
        input[@"native_end_of_day"] = @(anchor.timeIntervalSince1970);
    NSDictionary *data = IEBNativeChartData(input, &error);
    BOOL valid = data && !error;
    if (!valid) {
        double now = NSDate.date.timeIntervalSince1970;
        data = IEBNativeChartData(@{
            @"range" : @{@"start" : @(now - 1), @"end" : @(now)},
            @"levels" : @[],
            @"activity_buckets" : @[]
        },
                                  NULL);
    }
    self.configuring = YES;
    self.data = valid ? data : nil;
    ((void (*)(id, SEL))objc_msgSend)(self.chart, NSSelectorFromString(@"beginUpdate"));
    ((void (*)(id, SEL, id, id))objc_msgSend)(self.chart, NSSelectorFromString(@"setDataset:endOfDay:"),
                                              data[@"dataset"], data[@"end_of_day"]);
    // The native margin/background setters force-unwrap the model created by setDataset:.
    if (self.presentation[@"top_margin"] && self.presentation[@"bottom_margin"] &&
        MethodABI(NativeClass(), @"setMarginWithTop:bottom:", NO, "v32@0:8d16d24"))
        ((void (*)(id, SEL, double, double))objc_msgSend)(self.chart,
                                                          sel_registerName("setMarginWithTop:bottom:"),
                                                          [self.presentation[@"top_margin"] doubleValue],
                                                          [self.presentation[@"bottom_margin"] doubleValue]);
    if ([self.presentation[@"background"] isKindOfClass:UIColor.class] &&
        MethodABI(NativeClass(), @"setContainerBackgroundColor:", NO, "v24@0:8@16")) {
        Send(self.chart, @"setContainerBackgroundColor:", self.presentation[@"background"]);
        self.view.backgroundColor = self.presentation[@"background"];
    }
    id identifier =
        ((id(*)(id, SEL))objc_msgSend)(NativeClass(), NSSelectorFromString(@"chartIdentifier24Hrs"));
    Send(self.chart, @"setActiveChart:", identifier);
    NSNumber *selected = nil;
    if (valid && start > 0 && end > start)
        for (int i = 0; i < 24; i++) {
            NSDictionary *bucket = IEBNativeChartSelection(data, @(i));
            if (bucket && start >= [bucket[@"start"] doubleValue] && start < [bucket[@"end"] doubleValue]) {
                selected = @(i);
                break;
            }
        }
    Send(self.chart, @"setTappedIndex:", selected);
    ((void (*)(id, SEL))objc_msgSend)(self.chart, NSSelectorFromString(@"endUpdate"));
    self.configuring = NO;
    self.view.userInteractionEnabled = valid;
    return valid;
}
- (void)graphOnSelectAt:(NSNumber *)index {
    if (!self.configuring && self.data && self.selection)
        self.selection(IEBNativeChartSelection(self.data, index));
}
@end
