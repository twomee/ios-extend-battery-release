#import "../Sources/Presentation/IEBCycleHistoryController.h"
#import "../Sources/Presentation/IEBNativeBatteryCells.h"
#import "../Sources/Presentation/IEBNativeChartController.h"
#import "../Sources/Presentation/IEBProcessesController.h"
#import "../Sources/Presentation/IEBSettingsPanel.h"
#import "../Sources/Presentation/IEBStatisticsController.h"
#import "../Sources/Statistics/IEBStatisticsModel.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <unistd.h>
static UILabel *RowLabel(UITableViewCell *cell, NSString *key, UILabel *fallback) {
    return [cell respondsToSelector:NSSelectorFromString(key)] ? [cell valueForKey:key] : fallback;
}
@interface UIView (FixtureChartTap)
- (void)tap:(UITapGestureRecognizer *)tap;
@end
@interface FixtureTap : UITapGestureRecognizer
@property(nonatomic) CGPoint point;
@end
@implementation FixtureTap
- (CGPoint)locationInView:(UIView *)view {
    (void)view;
    return self.point;
}
@end
static void ChartTap(UIView *chart, double time) {
    FixtureTap *tap = [FixtureTap new];
    tap.point = CGPointMake(35 + (time - 1000) / 335 * MAX(1, chart.bounds.size.width - 47), 50);
    [chart tap:tap];
}
@interface NativeRangeFixture : UIViewController
@property(nonatomic, strong) id first, second;
- (void)setBatteryUIQueryRange:(id)value specifier:(id)specifier;
- (void)rangeChanged:(UISegmentedControl *)sender;
@end
@implementation NativeRangeFixture
- (void)setBatteryUIQueryRange:(id)value specifier:(id)specifier {
    self.first = value;
    self.second = specifier;
}
- (void)rangeChanged:(UISegmentedControl *)sender {
    self.first = @(sender.selectedSegmentIndex);
    self.second = @"control";
}
@end
static NSArray<NSString *> *FixtureRangeItems(void) {
    return @[ IEBLocalized(@"24H", @"24h"), IEBLocalized(@"10D", @"10d"), IEBLocalized(@"SINCE", @"Since") ];
}
static BOOL RangeQA(void) {
    NativeRangeFixture *owner = [NativeRangeFixture new];
    id specifier = [NSObject new];
    UISegmentedControl *direct = [[UISegmentedControl alloc] initWithItems:FixtureRangeItems()];
    direct.selectedSegmentIndex = 2;
    BOOL a = IEBSelectNativeRange(owner, direct, specifier, NO, 1) && [owner.first isEqual:@1] &&
             owner.second == specifier && direct.selectedSegmentIndex == 1;
    BOOL b = IEBSelectNativeRange(owner, nil, specifier, YES, 0) && owner.first == specifier &&
             [owner.second isEqual:@0];
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:FixtureRangeItems()];
    [control addTarget:owner action:@selector(rangeChanged:) forControlEvents:UIControlEventValueChanged];
    BOOL c = IEBSelectNativeRange(owner, control, nil, NO, 1) && [owner.first isEqual:@1] &&
             [owner.second isEqual:@"control"];
    UISegmentedControl *rebuilt = [[UISegmentedControl alloc] initWithItems:FixtureRangeItems()];
    rebuilt.selectedSegmentIndex = 2;
    IEBRememberSettingsRange(owner, 0);
    IEBSyncSettingsRange(owner, rebuilt);
    BOOL zero = rebuilt.selectedSegmentIndex == 0;
    IEBRememberSettingsRange(owner, 1);
    IEBSyncSettingsRange(owner, rebuilt);
    return a && b && c && zero && rebuilt.selectedSegmentIndex == 1;
}
// Real UITableView fixture: native rows remain interactive, only rows after range are replaced.
@interface HeaderFixture : NSObject <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UISegmentedControl *range;
@property(nonatomic) BOOL tappedHealth;
@end
@implementation HeaderFixture
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    (void)table;
    return 3;
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;
    return section == 1 ? 3 : 2;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:nil];
    cell.textLabel.text = index.section == 0
                              ? IEBLocalized(@"BATTERY_HEALTH", @"Battery Health")
                              : IEBLocalized(@"NATIVE_BATTERY_CONTENT", @"Native battery content");
    if (index.section == 1 && index.row == 0) {
        if (!self.range)
            self.range = [[UISegmentedControl alloc] initWithItems:FixtureRangeItems()];
        cell.textLabel.text = nil;
        self.range.selectedSegmentIndex = 2;
        self.range.frame = CGRectMake(16, 5, 340, 32);
        [cell.contentView addSubview:self.range];
    }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    self.tappedHealth = index.section == 0;
}
@end
static UITableView *HeaderTable(UIViewController *owner, HeaderFixture *source, BOOL root) {
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)
                                                      style:UITableViewStyleInsetGrouped];
    table.dataSource = source;
    table.delegate = source;
    table.rowHeight = 60;
    if (root)
        owner.view = table;
    else {
        owner.view.frame = table.frame;
        [owner.view addSubview:table];
    }
    [table reloadData];
    [table layoutIfNeeded];
    return table;
}
static BOOL PanelQA(void) {
    BOOL all = RangeQA();
    for (int scenario = 0; scenario < 2; scenario++) {
        UIViewController *owner = [UIViewController new];
        HeaderFixture *source = [HeaderFixture new];
        UITableView *table = HeaderTable(owner, source, scenario == 0);
        UIView *oldFooter = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 20)];
        table.tableFooterView = oldFooter;
        CGRect before = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        IEBStatisticsController *stats =
            [[IEBStatisticsController alloc] initWithLoader:^NSDictionary *(double a, double b, NSError **e) {
                (void)a;
                (void)b;
                (void)e;
                return @{@"state" : @"waiting"};
            }];
        IEBShowSettingsPanel(owner, source.range, stats, ^(NSInteger range) {
            (void)range;
            IEBDismissSettingsPanel(owner);
        });
        [table layoutIfNeeded];
        IEBLayoutSettingsPanel(owner);
        CGRect after = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        BOOL preserved = CGRectEqualToRect(before, after) && table.scrollEnabled &&
                         table.panGestureRecognizer.enabled && !stats.tableView.scrollEnabled;
        BOOL prefix = [table numberOfSections] == 2 && [table numberOfRowsInSection:1] == 1 &&
                      table.tableFooterView == stats.view &&
                      stats.view.frame.origin.y >=
                          CGRectGetMaxY([table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0
                                                                                        inSection:1]]);
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        CGFloat height = stats.view.bounds.size.height;
        table.contentOffset = CGPointMake(0, 150);
        IEBRebindSettingsPanel(owner, nil);
        BOOL survives = IEBHasSettingsPanel(owner) && table.tableFooterView == stats.view &&
                        fabs(height - stats.view.bounds.size.height) < 1;
        table.frame = CGRectMake(0, 0, 800, 400);
        IEBLayoutSettingsPanel(owner);
        BOOL rotated = fabs(stats.view.bounds.size.width - table.bounds.size.width) < 1;
        HeaderFixture *replacementSource = [HeaderFixture new];
        UITableView *replacement = HeaderTable(owner, replacementSource, YES);
        IEBRebindSettingsPanel(owner, replacementSource.range);
        [replacement layoutIfNeeded];
        BOOL rebound = replacement.tableFooterView == stats.view && [replacement numberOfSections] == 2 &&
                       table.dataSource == source && table.tableFooterView == oldFooter;
        IEBDismissSettingsPanel(owner);
        [replacement layoutIfNeeded];
        rebound &= replacement.dataSource == replacementSource && [replacement numberOfSections] == 3;
        IEBDismissSettingsPanel(owner);
        [table layoutIfNeeded];
        all &= rebound && preserved && prefix && source.tappedHealth && survives && rotated &&
               table.dataSource == source && table.tableFooterView == oldFooter &&
               [table numberOfSections] == 3 && [table numberOfRowsInSection:1] == 3;
    }
    return all;
}
static void RefreshQA(void (^completion)(BOOL)) {
    __block NSUInteger loads = 0;
    NSLock *lock = [NSLock new];
    IEBStatisticsController *test = [[IEBStatisticsController alloc]
        initWithLoader:^NSDictionary *(double a, double b, NSError **e) {
            (void)a;
            (void)b;
            (void)e;
            [lock lock];
            loads++;
            [lock unlock];
            [NSThread sleepForTimeInterval:0.15];
            return @{@"state" : @"waiting", @"apps" : @[]};
        }
        catalogProvider:^NSDictionary *(NSArray *ids) {
            (void)ids;
            return @{};
        }];
    [test loadViewIfNeeded];
    [test viewWillAppear:NO];
    for (int i = 0; i < 20; i++)
        [test.refreshControl sendActionsForControlEvents:UIControlEventValueChanged];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [lock lock];
        NSUInteger count = loads;
        [lock unlock];
        BOOL good = count <= 2 && [test valueForKey:@"model"] != nil;
        [test viewWillDisappear:NO];
        completion(good);
    });
}
static void CycleQA(void (^completion)(BOOL)) {
    NSLock *lock = [NSLock new];
    __block double cycle = 1000;
    __block BOOL staleQuery = NO;
    IEBStatisticsController *test = [[IEBStatisticsController alloc]
        initWithLoader:^NSDictionary *(double a, double b, NSError **e) {
            (void)e;
            [lock lock];
            double base = cycle;
            if (a && a < base)
                staleQuery = YES;
            [lock unlock];
            double start = a ?: base, end = b ?: base + 300;
            return @{
                @"state" : @"observed",
                @"window" : @{@"start" : @(base), @"effective_end" : @(base + 300)},
                @"range" : @{@"start" : @(start), @"end" : @(end)},
                @"apps" : @[],
                @"activity_buckets" : @[
                    @{@"start" : @(start),
                      @"end" : @(end),
                      @"ScreenOn" : @20,
                      @"ScreenOff" : @0}
                ],
                @"levels" : @[],
                @"energy_error" : NSNull.null,
                @"levels_error" : NSNull.null
            };
        }
        catalogProvider:^NSDictionary *(NSArray *ids) {
            (void)ids;
            return @{};
        }];
    [test loadViewIfNeeded];
    [test viewWillAppear:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        UITableViewCell *cell = [test tableView:test.tableView
                          cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        ChartTap(cell.contentView.subviews.lastObject, 1090);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            BOOL selected = [[test valueForKey:@"selectedStart"] doubleValue] > 0;
            UITableViewCell *chosen = [test tableView:test.tableView
                                cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
            ChartTap(chosen.contentView.subviews.lastObject, 1090);
            BOOL toggled = [[test valueForKey:@"selectedStart"] doubleValue] == 0;
            ChartTap(chosen.contentView.subviews.lastObject, 1090);
            [lock lock];
            cycle = 2000;
            [lock unlock];
            [test.refreshControl sendActionsForControlEvents:UIControlEventValueChanged];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(),
                           ^{
                               NSDictionary *model = [test valueForKey:@"model"];
                               [lock lock];
                               BOOL noStale = !staleQuery;
                               [lock unlock];
                               BOOL good = selected && toggled && noStale &&
                                           [[test valueForKey:@"selectedStart"] doubleValue] == 0 &&
                                           [model[@"range"][@"start"] doubleValue] == 2000;
                               [test viewWillDisappear:NO];
                               completion(good);
                           });
        });
    });
}
@interface UIViewController (NativeFixtureDelegate)
- (void)graphOnSelectAt:(NSNumber *)index;
- (void)refresh;
@end
@interface NativeChartFixture : UIViewController
@property(nonatomic, weak) UIViewController *delegate;
@property(nonatomic, strong) NSDictionary *dataset;
@property(nonatomic, strong) NSDate *endOfDay;
@property(nonatomic, strong) NSNumber *tapped;
@property(nonatomic) BOOL updating;
@property(nonatomic) double nativeTop, nativeBottom;
@property(nonatomic) BOOL nativeModelReady;
@property(nonatomic) NSUInteger nativeInitializationViolations;
@property(nonatomic, strong) UIColor *nativeBackground;
@end
@implementation NativeChartFixture
+ (id)chartIdentifier24Hrs {
    return @"24h";
}
+ (double)graphHeightWithTraitCollection:(UITraitCollection *)traits {
    (void)traits;
    return 330;
}
- (void)setMarginWithTop:(double)top bottom:(double)bottom {
    if (!self.nativeModelReady)
        self.nativeInitializationViolations++;
    self.nativeTop = top;
    self.nativeBottom = bottom;
}
- (void)setContainerBackgroundColor:(UIColor *)color {
    if (!self.nativeModelReady)
        self.nativeInitializationViolations++;
    self.nativeBackground = color;
}
- (void)beginUpdate {
    self.updating = YES;
}
- (void)endUpdate {
    self.updating = NO;
}
- (void)setActiveChart:(id)chart {
    (void)chart;
}
- (void)setTappedIndex:(id)index {
    self.tapped = index;
    [self.delegate graphOnSelectAt:index];
}
- (void)setDataset:(id)dataset endOfDay:(id)day {
    self.nativeModelReady = YES;
    self.dataset = dataset;
    self.endOfDay = day;
    [self.delegate graphOnSelectAt:@0];
}
@end
@interface NativeTimeFixture : UITableViewCell {
    UILabel *_screenOnTimeText;
    UILabel *_screenOffTimeText;
}
@end
@implementation NativeTimeFixture
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        _screenOnTimeText = [UILabel new];
        _screenOffTimeText = [UILabel new];
        _screenOnTimeText.text = @"original-on";
        _screenOffTimeText.text = @"original-off";
        [self.contentView addSubview:_screenOnTimeText];
        [self.contentView addSubview:_screenOffTimeText];
    }
    return self;
}
- (NSString *)getLoczlizedHourMinuteStringFromSeconds:(double)seconds {
    return [NSString stringWithFormat:@"native:%.0f", floor(seconds / 60)];
}
@end
@interface NativeGraphFixture : UITableViewCell {
    UIViewController *_controller;
}
@end
@implementation NativeGraphFixture
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        _controller = [[NSClassFromString(@"_TtC14BatteryUsageUI24PLBUIChartViewController") alloc]
            initWithNibName:nil
                     bundle:nil];
        [self.contentView addSubview:_controller.view];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _controller.view.frame = self.contentView.bounds;
    IEBLayoutNativeChart(self);
}
@end
@interface NativeSpecifierFixture : NSObject
@property(nonatomic) Class nativeCellClass;
@end
@implementation NativeSpecifierFixture
- (id)propertyForKey:(NSString *)key {
    return [key isEqual:@"cellClass"] ? self.nativeCellClass : nil;
}
@end
@interface NativeRowsFixture : NSObject <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UISegmentedControl *range;
@property(nonatomic, strong) UITableViewCell *graph, *summary;
@property(nonatomic) BOOL discovering;
@property(nonatomic) NSUInteger discoveryCellRequests;
@end
@implementation NativeRowsFixture
- (id)specifierAtIndexPath:(NSIndexPath *)path {
    NativeSpecifierFixture *specifier = [NativeSpecifierFixture new];
    specifier.nativeCellClass = path.row == 2   ? NSClassFromString(@"PLBatteryUIGraphViewTableCell")
                                : path.row == 3 ? NSClassFromString(@"PLBatteryUITimeUsageCell")
                                                : UITableViewCell.class;
    return specifier;
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return 5;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    return index.row == 2 ? 330 : index.row == 3 ? 80 : 50;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    if (self.discovering && table.dataSource == self)
        self.discoveryCellRequests++;
    if (index.row == 2) {
        if (!self.graph)
            self.graph = [[NSClassFromString(@"PLBatteryUIGraphViewTableCell") alloc] initWithStyle:0
                                                                                    reuseIdentifier:nil];
        return self.graph;
    }
    if (index.row == 3) {
        if (!self.summary)
            self.summary = [[NSClassFromString(@"PLBatteryUITimeUsageCell") alloc] initWithStyle:0
                                                                                 reuseIdentifier:nil];
        return self.summary;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:0 reuseIdentifier:nil];
    if (index.row == 1) {
        if (!self.range)
            self.range = [[UISegmentedControl alloc] initWithItems:FixtureRangeItems()];
        [cell.contentView addSubview:self.range];
    }
    return cell;
}
@end
static NSDictionary *NativeSpacingMeasurements;
static BOOL NativeLayoutQA(void) {
    objc_registerClassPair(objc_allocateClassPair(NativeTimeFixture.class, "PLBatteryUITimeUsageCell", 0));
    objc_registerClassPair(
        objc_allocateClassPair(NativeGraphFixture.class, "PLBatteryUIGraphViewTableCell", 0));
    UIViewController *owner = [UIViewController new];
    NativeRowsFixture *source = [NativeRowsFixture new];
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 400, 900)
                                                      style:UITableViewStyleGrouped];
    owner.view = table;
    table.dataSource = source;
    table.delegate = source;
    [table reloadData];
    [table layoutIfNeeded];
    NSIndexPath *graphPath = [NSIndexPath indexPathForRow:2 inSection:0],
                *timePath = [NSIndexPath indexPathForRow:3 inSection:0];
    CGRect graphBefore = [table rectForRowAtIndexPath:graphPath],
           timeBefore = [table rectForRowAtIndexPath:timePath];
    IEBStatisticsController *stats =
        [[IEBStatisticsController alloc] initWithLoader:^NSDictionary *(double a, double b, NSError **e) {
            (void)a;
            (void)b;
            (void)e;
            return @{@"state" : @"waiting"};
        }];
    source.discovering = YES;
    BOOL shown = IEBShowSettingsPanel(owner, source.range, stats, nil);
    source.discovering = NO;
    [table layoutIfNeeded];
    BOOL stable = source.discoveryCellRequests == 0 && shown && [table numberOfRowsInSection:0] == 4 &&
                  stats.nativeTablePresentation &&
                  CGRectEqualToRect(graphBefore, [table rectForRowAtIndexPath:graphPath]) &&
                  CGRectEqualToRect(timeBefore, [table rectForRowAtIndexPath:timePath]);
    [stats setValue:@{@"screen_on" : @3601, @"screen_off" : NSNull.null} forKey:@"model"];
    [stats.tableView reloadData];
    IEBLayoutSettingsPanel(owner);
    [table layoutIfNeeded];
    CGRect firstHeader = [stats.tableView rectForHeaderInSection:0];
    CGRect inNative = [stats.tableView convertRect:firstHeader toView:table];
    double gap = inNative.origin.y - CGRectGetMaxY([table rectForRowAtIndexPath:timePath]);
    NativeSpacingMeasurements = @{
        @"gap" : @(gap),
        @"footer_header_y" : @(firstHeader.origin.y),
        @"footer_y" : @(stats.view.frame.origin.y)
    };
    stable &= gap <= 64 && gap >= 0 && [stats.tableView numberOfSections] == 4;
    [stats updateNativeTimeUsageCell:source.summary];
    BOOL formatted = [[source.summary valueForKey:@"_screenOnTimeText"] text] &&
                     [[[source.summary valueForKey:@"_screenOnTimeText"] text] isEqual:@"native:60"] &&
                     [[[source.summary valueForKey:@"_screenOffTimeText"] text] isEqual:@"—"];
    BOOL overlay = stats.nativeChartView.nextResponder != nil && owner.childViewControllers.count == 2 &&
                   IEBOriginalChartController(source.graph).view.hidden &&
                   [stats.nativeChartView isDescendantOfView:source.graph];
    for (int i = 0; i < 3; i++)
        IEBRebindSettingsPanel(owner, source.range);
    stable &= CGRectEqualToRect(graphBefore, [table rectForRowAtIndexPath:graphPath]);
    table.dataSource = source;
    [table reloadData];
    IEBLayoutSettingsPanel(owner);
    [table layoutIfNeeded];
    stable &= [table numberOfRowsInSection:0] == 4 && stats.nativeChartView.superview != nil;
    [[source.summary valueForKey:@"_screenOnTimeText"] setText:@"native refresh"];
    IEBRefreshNativeTimeUsage(source.summary);
    formatted &= [[[source.summary valueForKey:@"_screenOnTimeText"] text] isEqual:@"native:60"];
    NativeRowsFixture *replacement = [NativeRowsFixture new];
    UITableView *newTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 600, 900)
                                                         style:UITableViewStyleGrouped];
    newTable.dataSource = replacement;
    newTable.delegate = replacement;
    owner.view = newTable;
    [newTable reloadData];
    [newTable layoutIfNeeded];
    CGRect newGraphBefore = [newTable rectForRowAtIndexPath:graphPath];
    IEBRebindSettingsPanel(owner, replacement.range);
    [newTable layoutIfNeeded];
    stable &= [newTable numberOfRowsInSection:0] == 4 &&
              CGRectEqualToRect(newGraphBefore, [newTable rectForRowAtIndexPath:graphPath]) &&
              [stats.nativeChartView isDescendantOfView:replacement.graph] &&
              CGRectEqualToRect(stats.nativeChartView.frame,
                                IEBOriginalChartController(replacement.graph).view.frame) &&
              !IEBOriginalChartController(source.graph).view.hidden;
    IEBDismissSettingsPanel(owner);
    stable &=
        [newTable numberOfRowsInSection:0] == 5 && !IEBOriginalChartController(replacement.graph).view.hidden;
    BOOL restored = owner.childViewControllers.count == 0 && [table numberOfRowsInSection:0] == 5 &&
                    !IEBOriginalChartController(source.graph).view.hidden &&
                    [[[source.summary valueForKey:@"_screenOnTimeText"] text] isEqual:@"original-on"];
    return stable && formatted && overlay && restored;
}
static BOOL NativeChartReuseQA(void) {
    UITableViewCell *first = [[NSClassFromString(@"PLBatteryUIGraphViewTableCell") alloc] initWithStyle:0
                                                                                        reuseIdentifier:nil];
    first.frame = CGRectMake(0, 0, 400, 330);
    [first layoutIfNeeded];
    UIViewController *shared = IEBOriginalChartController(first);
    UIView *replacement = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 330)];
    BOOL attached = IEBAttachNativeChart(first, replacement);
    UITableViewCell *second = [[NSClassFromString(@"PLBatteryUIGraphViewTableCell") alloc] initWithStyle:0
                                                                                         reuseIdentifier:nil];
    object_setIvar(second, class_getInstanceVariable(second.class, "_controller"), shared);
    [second.contentView addSubview:shared.view];
    second.frame = CGRectMake(0, 0, 600, 330);
    [second layoutIfNeeded];
    attached &= IEBAttachNativeChart(second, replacement);
    IEBRestoreNativeChart(first);
    BOOL retained = shared.view.hidden && [replacement isDescendantOfView:second];
    IEBRestoreNativeChart(second);
    BOOL restored = !shared.view.hidden && !replacement.superview;
    UIViewController *survivor;
    __weak UITableViewCell *releasedCell;
    @autoreleasepool {
        UITableViewCell *ephemeral =
            [[NSClassFromString(@"PLBatteryUIGraphViewTableCell") alloc] initWithStyle:0 reuseIdentifier:nil];
        ephemeral.frame = CGRectMake(0, 0, 400, 330);
        [ephemeral layoutIfNeeded];
        survivor = IEBOriginalChartController(ephemeral);
        releasedCell = ephemeral;
        attached &= IEBAttachNativeChart(ephemeral, replacement);
    }
    BOOL released = releasedCell == nil && survivor.view.hidden;
    IEBRestoreNativeChartView(replacement);
    BOOL ownerRestored = !survivor.view.hidden && !replacement.superview;
    return attached && retained && restored && released && ownerRestored;
}
@interface ReportPresentationFixture : IEBStatisticsController
@property(nonatomic, strong) UIViewController *capturedPresentation;
@end
@implementation ReportPresentationFixture
- (void)presentViewController:(UIViewController *)controller
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion {
    (void)animated;
    self.capturedPresentation = controller;
    if (completion)
        completion();
}
@end
static BOOL ReportPresentationQA(void) {
    ReportPresentationFixture *stats =
        [[ReportPresentationFixture alloc] initWithLoader:^NSDictionary *(double a, double b, NSError **e) {
            (void)a;
            (void)b;
            (void)e;
            return nil;
        }];
    [stats loadViewIfNeeded];
    [stats setValue:@{
        @"state" : @"observed",
        @"range" : @{@"start" : @100, @"end" : @400},
        @"window" : @{@"start" : @100},
        @"activity_latest_end" : @160
    }
             forKey:@"model"];
    NSString *header = [stats tableView:stats.tableView titleForHeaderInSection:3];
    BOOL quality = [header containsString:@"00:04:00"] && [header containsString:@"00:01:00"];
    UITableViewCell *exportRow = [stats tableView:stats.tableView
                            cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:6]];
    BOOL rows =
        [stats tableView:stats.tableView numberOfRowsInSection:6] == 3 &&
        [exportRow.textLabel.text
            isEqual:IEBLocalized(@"EXPORT_DIAGNOSTIC_REPORT", @"Export Diagnostic Report")] &&
        [exportRow.detailTextLabel.text
            isEqual:IEBLocalized(
                        @"READABLE_TXT_IN_THE_INTERFACE_LANGUAGE_AND_TECHNICAL_JSON_AGGREGATE_DATA_ON",
                        @"Readable TXT in the interface language and technical JSON · aggregate data only. "
                        @"Choose where to share.")];
    NSArray *before = [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSTemporaryDirectory()
                                                                        error:NULL];
    [stats tableView:stats.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:6]];
    BOOL share = [stats.capturedPresentation isKindOfClass:UIActivityViewController.class];
    NSMutableSet *created = [NSMutableSet
        setWithArray:[NSFileManager.defaultManager contentsOfDirectoryAtPath:NSTemporaryDirectory()
                                                                       error:NULL]];
    [created minusSet:[NSSet setWithArray:before]];
    [created
        filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            (void)bindings;
            return [name hasPrefix:@"IEBDiagnosticExport-"];
        }]];
    NSString *directory =
        created.count == 1 ? [NSTemporaryDirectory() stringByAppendingPathComponent:created.anyObject] : nil;
    BOOL files =
        directory && [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL].count == 2;
    UIActivityViewController *sheet = (UIActivityViewController *)stats.capturedPresentation;
    if (share && sheet.completionWithItemsHandler)
        sheet.completionWithItemsHandler(nil, NO, nil, nil);
    BOOL cancelled = directory && ![NSFileManager.defaultManager fileExistsAtPath:directory];
    stats.nativeTablePresentation = YES;
    stats.capturedPresentation = nil;
    [stats tableView:stats.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:3]];
    BOOL native = [stats.capturedPresentation isKindOfClass:UIActivityViewController.class];
    sheet = (UIActivityViewController *)stats.capturedPresentation;
    if (native && sheet.completionWithItemsHandler)
        sheet.completionWithItemsHandler(nil, YES, nil, nil);
    BOOL completedClean = YES;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSTemporaryDirectory()
                                                                             error:NULL])
        if ([name hasPrefix:@"IEBDiagnosticExport-"] && ![before containsObject:name])
            completedClean = NO;
    return quality && rows && share && native && files && cancelled && completedClean;
}
static BOOL NativeSectionRoutingQA(void) {
    IEBStatisticsController *stats =
        [[IEBStatisticsController alloc] initWithLoader:^NSDictionary *(double a, double b, NSError **error) {
            (void)a;
            (void)b;
            (void)error;
            return nil;
        }];
    stats.nativeTablePresentation = YES;
    [stats loadViewIfNeeded];
    [stats setValue:@{@"state" : @"active"} forKey:@"model"];
    [stats setValue:@{
        @"applications" : @[
            @{@"id" : @"routing.app",
              @"percent" : @10}
        ],
        @"system_processes" : @[]
    }
             forKey:@"groups"];
    UITableViewCell *app = [stats tableView:stats.tableView
                      cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    BOOL appCorrect = [[[app valueForKey:@"nameLabel"] text] isEqual:@"routing.app"];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:stats];
    [stats tableView:stats.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    BOOL details = [NSStringFromClass(navigation.topViewController.class) isEqual:@"IEBDetails"];
    [navigation popToRootViewControllerAnimated:NO];
    [stats tableView:stats.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
    BOOL processes = [navigation.topViewController isKindOfClass:IEBProcessesController.class];
    [navigation popToRootViewControllerAnimated:NO];
    [stats setValue:@{@"state" : @"waiting"} forKey:@"model"];
    BOOL waiting = [stats numberOfSectionsInTableView:stats.tableView] == 2 &&
                   [stats tableView:stats.tableView numberOfRowsInSection:0] == 1;
    [stats setValue:@{@"state" : @"active"} forKey:@"model"];
    stats.nativeTablePresentation = NO;
    BOOL fallback =
        !stats.tableView.tableHeaderView && [stats numberOfSectionsInTableView:stats.tableView] == 7;
    stats.nativeTablePresentation = YES;
    BOOL rebound = stats.tableView.tableHeaderView && stats.tableView.tableHeaderView.frame.size.height < 1 &&
                   [stats numberOfSectionsInTableView:stats.tableView] == 4;
    return appCorrect && details && processes && waiting && fallback && rebound;
}
static BOOL UnavailableDiagnosticsQA(void) {
    for (NSNumber *native in @[ @NO, @YES ])
        for (id state in @[ NSNull.null, @{@"state" : @"waiting"} ]) {
            ReportPresentationFixture *stats = [[ReportPresentationFixture alloc]
                initWithLoader:^NSDictionary *(double a, double b, NSError **error) {
                    (void)a;
                    (void)b;
                    (void)error;
                    return nil;
                }];
            [stats loadViewIfNeeded];
            stats.nativeTablePresentation = native.boolValue;
            [stats setValue:state == NSNull.null ? nil : state forKey:@"model"];
            if ([stats numberOfSectionsInTableView:stats.tableView] != 2 || [stats tableView:stats.tableView
                                                                                numberOfRowsInSection:1] < 2)
                return NO;
            for (NSInteger row = 0; row < 2; row++) {
                UITableViewCell *cell = [stats tableView:stats.tableView
                                   cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
                if (cell.selectionStyle == UITableViewCellSelectionStyleNone)
                    return NO;
            }
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:stats];
            [stats tableView:stats.tableView
                didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
            if (![nav.topViewController isKindOfClass:IEBProcessesController.class])
                return NO;
            [nav popToRootViewControllerAnimated:NO];
            [stats tableView:stats.tableView
                didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]];
            if (![stats.capturedPresentation isKindOfClass:UIActivityViewController.class])
                return NO;
            UIActivityViewController *share = (UIActivityViewController *)stats.capturedPresentation;
            if (share.completionWithItemsHandler)
                share.completionWithItemsHandler(nil, NO, nil, nil);
            [stats tableView:stats.tableView
                didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]];
            if (![nav.topViewController isKindOfClass:IEBCycleHistoryController.class])
                return NO;
        }
    return YES;
}
static BOOL NativeChartQA(void) {
    Class fake =
        objc_allocateClassPair(NativeChartFixture.class, "_TtC14BatteryUsageUI24PLBUIChartViewController", 0);
    objc_registerClassPair(fake);
    __block NSUInteger calls = 0;
    __block NSDictionary *selection = nil;
    IEBNativeChartController *host =
        [[IEBNativeChartController alloc] initWithSelection:^(NSDictionary *range) {
            calls++;
            selection = range;
        }];
    NSDictionary *model =
        @{@"range" : @{@"start" : @100000, @"end" : @103685},
          @"levels" : @[],
          @"activity_buckets" : @[]};
    UIViewController *original = [[fake alloc] initWithNibName:nil bundle:nil];
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 400, 600)
                                                      style:UITableViewStyleGrouped];
    UITableViewCell *originalCell = [[UITableViewCell alloc] initWithFrame:CGRectMake(0, 0, 400, 330)];
    [table addSubview:originalCell];
    original.view.frame = CGRectMake(12, 0, 376, 330);
    [originalCell addSubview:original.view];
    IEBRememberNativeChartMargins(original, 8, 12);
    IEBRememberNativeChartBackground(original, UIColor.secondarySystemGroupedBackgroundColor);
    IEBRememberNativeChartAnchor(original, [NSDate dateWithTimeIntervalSince1970:108000]);
    IEBRememberNativeChartLayout(originalCell, original);
    host.presentation = IEBNativeChartPresentationForTable(table);
    BOOL captured = host.presentation && [host.presentation[@"left"] doubleValue] == 12 &&
                    [host.presentation[@"right"] doubleValue] == 12;
    BOOL configured = [host configureOverview:model selectedStart:100800 selectedEnd:103685];
    NativeChartFixture *native = [host valueForKey:@"chart"];
    BOOL suppressed =
        calls == 0 && native.tapped.integerValue == 22 && native.endOfDay.timeIntervalSince1970 == 108000 &&
        native.nativeTop == 8 && native.nativeBottom == 12 && native.nativeBackground != nil &&
        native.nativeInitializationViolations == 0 &&
        [native.dataset[@"PLBatteryUIGraph24hrs"][@"PLBatteryUIBatteryLevelsKey"] count] == 96 &&
        !native.updating;
    [host loadViewIfNeeded];
    // The custom table cell has an extra inset: plot geometry must still match the native table coordinates.
    UITableViewCell *chartCell = [host makeChartCell];
    chartCell.frame = CGRectMake(20, 0, 360, 330);
    [table addSubview:chartCell];
    [chartCell layoutIfNeeded];
    CGRect actual = [host.view convertRect:host.view.bounds toView:table];
    BOOL geometry = fabs(actual.origin.x - 12) < 0.5 && fabs(actual.size.width - 376) < 0.5;
    CGPoint edge = [chartCell convertPoint:CGPointMake(1, 10) fromView:host.view];
    geometry &= [chartCell pointInside:edge withEvent:nil] && [chartCell hitTest:edge withEvent:nil] != nil;
    table.frame = CGRectMake(0, 0, 600, 600);
    [chartCell setNeedsLayout];
    [chartCell layoutIfNeeded];
    actual = [host.view convertRect:host.view.bounds toView:table];
    geometry &= fabs(actual.origin.x - 12) < 0.5 && fabs(actual.size.width - 576) < 0.5;
    // A custom dataset must never overwrite the captured native anchor.
    IEBRememberNativeChartAnchor(native, [NSDate dateWithTimeIntervalSince1970:111600]);
    IEBRememberNativeChartLayout(chartCell, native);
    BOOL isolated =
        [IEBNativeChartPresentationForTable(table)[@"end_of_day"] timeIntervalSince1970] == 108000;
    [native.delegate graphOnSelectAt:@22];
    BOOL selected = calls == 1 && [selection[@"end"] doubleValue] == 103685;
    [native.delegate graphOnSelectAt:nil];
    BOOL nativeLayout = NativeLayoutQA();
    BOOL nativeReuse = NativeChartReuseQA();
    BOOL routing = NativeSectionRoutingQA();
    BOOL cleared =
        ![host configureOverview:@{} selectedStart:0 selectedEnd:0] && !host.view.userInteractionEnabled;
    for (NSArray *point in native.dataset[@"PLBatteryUIGraph24hrs"][@"PLBatteryUIBatteryLevelsKey"])
        cleared &= [point[0] doubleValue] == -1;
    return routing && nativeReuse && cleared && nativeLayout && captured && geometry && isolated &&
           configured && suppressed && selected && calls == 2 && !selection &&
           host.childViewControllers.count == 1 &&
           [IEBNativeChartController heightForTraits:host.traitCollection] == 330;
}
static void SaveQAWindow(UIWindow *window, NSString *name) {
    [window layoutIfNeeded];
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, 0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSString *directory =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:name]
                                      atomically:YES];
}
@interface UITableViewController (IEBComparisonTesting)
- (instancetype)initWithFirst:(NSDictionary *)first second:(NSDictionary *)second;
@end
static BOOL ComparisonTextQA(void) {
    NSDictionary *a = @{@"duration" : @19.39, @"screen_on" : @19.39, @"screen_off" : @0.2};
    NSDictionary *b = @{@"duration" : @5654, @"screen_on" : @5566.88, @"screen_off" : @0.1};
    UITableViewController *comparison =
        [(UITableViewController *)[NSClassFromString(@"IEBCycleComparisonController") alloc] initWithFirst:a
                                                                                                    second:b];
    [comparison loadViewIfNeeded];
    NSString *on = [comparison tableView:comparison.tableView
                       cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]]
                       .detailTextLabel.text;
    NSString *off = [comparison tableView:comparison.tableView
                        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]]
                        .detailTextLabel.text;
    NSString *missingEnergy = [comparison tableView:comparison.tableView
                                  cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]
                                  .detailTextLabel.text;
    BOOL good = [missingEnergy containsString:@"—"] && [on containsString:@"\u206600:00:19\u2069"] &&
                [on containsString:@"\u206601:32:47\u2069"] && [on containsString:@"\u2066−01:32:28\u2069"] &&
                [off containsString:@"\u206600:00:00\u2069"] && ![off containsString:@"+00:00:00"];
    comparison =
        [(UITableViewController *)[NSClassFromString(@"IEBCycleComparisonController") alloc] initWithFirst:b
                                                                                                    second:a];
    on = [comparison tableView:comparison.tableView
             cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]]
             .detailTextLabel.text;
    good &= [on containsString:@"\u2066+01:32:28\u2069"];
    NSMutableDictionary *ea = [@{
        @"duration" : @3600,
        @"energy_total" : @20.04,
        @"energy_per_hour" : @20.04,
        @"power_complete" : @YES,
        @"energy_coverage_known" : @YES,
        @"energy_partial" : @NO
    } mutableCopy];
    NSMutableDictionary *eb = [ea mutableCopy];
    eb[@"energy_total"] = @20.06;
    eb[@"energy_per_hour"] = @20.06;
    comparison = [(UITableViewController *)[NSClassFromString(@"IEBCycleComparisonController") alloc]
        initWithFirst:ea
               second:eb];
    NSString *energy = [comparison tableView:comparison.tableView
                           cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]
                           .detailTextLabel.text;
    good &=
        [energy containsString:@"\u20660.1%\u2069"] &&
        [energy containsString:[NSString
                                   stringWithFormat:IEBLocalized(@"A_S_ESTIMATED_RATE_IS_LOWER_THAN_B_S",
                                                                 @"A's estimated rate is %@ lower than B's."),
                                                    @"\u20660.1%\u2069"]] &&
        ![energy containsString:@"20.0"];
    ea[@"duration"] = @3600;
    ea[@"energy_per_hour"] = @1585414.2738826447;
    ea[@"energy_total"] = @([ea[@"energy_per_hour"] doubleValue]);
    eb[@"energy_total"] = @1237423.4380600983;
    eb[@"energy_per_hour"] = @1237423.4380600983;
    comparison = [(UITableViewController *)[NSClassFromString(@"IEBCycleComparisonController") alloc]
        initWithFirst:ea
               second:eb];
    UITableViewCell *relative = [comparison tableView:comparison.tableView
                                cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    good &=
        [relative.textLabel.text containsString:IEBLocalized(@"RELATIVE_CONSUMPTION_RATE_ESTIMATE",
                                                             @"Relative consumption rate — estimate")] &&
        [relative.detailTextLabel.text containsString:@"28.1%"] &&
        [relative.detailTextLabel.text
            containsString:[NSString
                               stringWithFormat:IEBLocalized(@"A_S_ESTIMATED_RATE_IS_HIGHER_THAN_B_S",
                                                             @"A's estimated rate is %@ higher than B's."),
                                                @"\u206628.1%\u2069"]] &&
        ![relative.detailTextLabel.text
            containsString:IEBLocalized(
                               @"A_CYCLE_IS_SHORTER_THAN_ONE_MINUTE_THERE_IS_NOT_ENOUGH_DATA_FOR_A_USEFUL_RA",
                               @"— · A cycle is shorter than one minute; there is not enough data for a "
                               @"useful rate comparison.")] &&
        ![relative.detailTextLabel.text containsString:@"1585414"];
    ea[@"duration"] = @19.39;
    ea[@"energy_total"] = @([ea[@"energy_per_hour"] doubleValue] * 19.39 / 3600);
    comparison = [(UITableViewController *)[NSClassFromString(@"IEBCycleComparisonController") alloc]
        initWithFirst:ea
               second:eb];
    energy = [comparison tableView:comparison.tableView
                 cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]
                 .detailTextLabel.text;
    good &=
        [energy containsString:@"—"] &&
        [energy
            containsString:IEBLocalized(
                               @"A_CYCLE_IS_SHORTER_THAN_ONE_MINUTE_THERE_IS_NOT_ENOUGH_DATA_FOR_A_USEFUL_RA",
                               @"— · A cycle is shorter than one minute; there is not enough data for a "
                               @"useful rate comparison.")] &&
        ![energy containsString:@"28.1%"];
    ea[@"duration"] = @3600;
    ea[@"energy_total"] = ea[@"energy_per_hour"];
    eb[@"energy_total"] = @0;
    eb[@"energy_per_hour"] = @0;
    comparison = [(UITableViewController *)[NSClassFromString(@"IEBCycleComparisonController") alloc]
        initWithFirst:ea
               second:eb];
    energy = [comparison tableView:comparison.tableView
                 cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]]
                 .detailTextLabel.text;
    good &=
        [energy
            containsString:IEBLocalized(
                               @"B_HAS_NO_POSITIVE_ESTIMATED_RATE_TO_USE_AS_A_COMPARISON_BASELINE",
                               @"— · B has no positive estimated rate to use as a comparison baseline.")] &&
        [energy containsString:@"—"];
    return good;
}
static void HistoryQA(void (^completion)(BOOL)) {
    __block NSUInteger details = 0;
    NSArray *records = @[
        @{
            @"id" : @"A",
            @"start" : @100,
            @"end" : @119.39,
            @"duration" : @19.39,
            @"screen_on" : @19.39,
            @"screen_off" : NSNull.null,
            @"power_complete" : @YES,
            @"activity_pending_seconds" : @0
        },
        @{
            @"id" : @"B",
            @"start" : @4000,
            @"end" : @9654,
            @"duration" : @5654,
            @"screen_on" : @5566.88,
            @"screen_off" : NSNull.null,
            @"power_complete" : @YES,
            @"activity_pending_seconds" : @120
        }
    ];
    IEBCycleHistoryController *history = [[IEBCycleHistoryController alloc]
        initWithListLoader:^NSArray *(NSError **error) {
            (void)error;
            return records;
        }
        detailLoader:^NSDictionary *(NSDictionary *record, NSError **error) {
            (void)error;
            details++;
            NSMutableDictionary *r = [record mutableCopy];
            BOOL a = [r[@"id"] isEqual:@"A"];
            r[@"energy_per_hour"] = a ? @1585414.2738826447 : @1237423.4380600983;
            r[@"energy_total"] = @([r[@"energy_per_hour"] doubleValue] * [r[@"duration"] doubleValue] / 3600);
            r[@"energy_coverage_known"] = @YES;
            r[@"energy_partial"] = @NO;
            r[@"energy_allocation_estimated"] = @YES;
            return r;
        }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:history];
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController = nav;
    [window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        SaveQAWindow(window, @"history.png");
        __block BOOL good = [[history tableView:history.tableView
                                titleForFooterInSection:0] containsString:@"PerfPowerServices"] &&
                            [history tableView:history.tableView numberOfRowsInSection:0] == 2 &&
                            details == 0;
        [history tableView:history.tableView
            didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        good &= details == 0;
        [history tableView:history.tableView
            didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            SaveQAWindow(window, @"comparison.png");
            UITableViewController *comparison = (UITableViewController *)nav.topViewController;
            BOOL pushed = comparison != history && [comparison isKindOfClass:UITableViewController.class];
            if (pushed) {
                UITableViewCell *energy = [comparison tableView:comparison.tableView
                                          cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
                good &= [energy.detailTextLabel.text containsString:@"—"] &&
                        [energy.detailTextLabel.text
                            containsString:IEBLocalized(@"A_CYCLE_IS_SHORTER_THAN_ONE_MINUTE_THERE_IS_NOT_"
                                                        @"ENOUGH_DATA_FOR_A_USEFUL_RA",
                                                        @"— · A cycle is shorter than one minute; there is "
                                                        @"not enough data for a useful rate comparison.")];
            }
            [history viewWillDisappear:NO];
            window.hidden = YES;
            completion(good && pushed && details == 2 && ComparisonTextQA());
        });
    });
}
// Wait for the real async loader to publish a sample; CI storage/CPU can exceed 250ms.
static void WaitForProcessSample(IEBProcessesController *list, NSUInteger remaining,
                                 void (^completion)(BOOL)) {
    BOOL loaded = [list valueForKey:@"snapshot"] && ![[list valueForKey:@"loading"] boolValue];
    if (loaded || remaining == 0) {
        completion(loaded);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        WaitForProcessSample(list, remaining - 1, completion);
    });
}
static void LiveProcessesQA(void (^completion)(BOOL)) {
    __block double sample = 0;
    IEBProcessesController *list = [[IEBProcessesController alloc] initWithLoader:^NSDictionary * {
        usleep(400000); // Slow process reads must not invalidate the asynchronous fixture.
        sample++;
        return @{
            @"snapshot" : @{
                @"rows" : @[
                    @{
                        @"pid" : @1,
                        @"name" : @"service",
                        @"start_ticks" : @5,
                        @"cpu_seconds" : @(10 + sample),
                        @"sampled_at" : @(100 + sample * 5)
                    },
                    @{
                        @"pid" : @2,
                        @"name" : @"other",
                        @"start_ticks" : @6,
                        @"cpu_seconds" : @(2 + sample * 0.2),
                        @"sampled_at" : @(100 + sample * 5)
                    }
                ],
                @"permission_denied_count" : @1,
                @"status" : @"partial"
            },
            @"sources" : @[
                @{@"id" : @"service",
                  @"percent" : @5}
            ],
            @"catalog" : @{}
        };
    }];
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:list];
    [window makeKeyAndVisible];
    WaitForProcessSample(list, 200, ^(BOOL loaded) {
        if (!loaded || ![list respondsToSelector:NSSelectorFromString(@"searchController")]) {
            [list viewWillDisappear:NO];
            window.hidden = YES;
            completion(NO);
            return;
        }
        UISearchController *search = [list valueForKey:@"searchController"];
        search.searchBar.text = @"service";
        [(id<UISearchResultsUpdating>)list updateSearchResultsForSearchController:search];
        [list refresh];
        WaitForProcessSample(list, 200, ^(BOOL refreshed) {
            if (!refreshed) {
                [list viewWillDisappear:NO];
                window.hidden = YES;
                completion(NO);
                return;
            }
            UITableViewCell *cell = [list tableView:list.tableView
                              cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            BOOL good = [list tableView:list.tableView numberOfRowsInSection:0] == 1 &&
                        [[cell valueForKey:@"percentLabel"] text] &&
                        [[[cell valueForKey:@"timesLabel"] text] containsString:@"20.0%"];
            search.searchBar.text = @"";
            [(id<UISearchResultsUpdating>)list updateSearchResultsForSearchController:search];
            NSArray *all = [list valueForKey:@"rows"];
            good &= all.count == 2 && [all[1][@"cpu_percent"] isKindOfClass:NSNumber.class];
            UISegmentedControl *sort = [list valueForKey:@"sortControl"];
            sort.selectedSegmentIndex = 3;
            [sort sendActionsForControlEvents:UIControlEventValueChanged];
            good &= [[[list valueForKey:@"rows"] firstObject][@"name"] isEqual:@"other"];
            SaveQAWindow(window, @"processes.png");
            search.searchBar.text = @"not-a-process";
            [(id<UISearchResultsUpdating>)list updateSearchResultsForSearchController:search];
            good &= [[list valueForKey:@"rows"] count] == 0 && [[list valueForKey:@"allRows"] count] == 2;
            [list viewWillDisappear:NO];
            window.hidden = YES;
            completion(good);
        });
    });
}
@interface PreviewDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation PreviewDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app;
    (void)options;
    IEBStatisticsController *controller = [[IEBStatisticsController alloc]
        initWithLoader:^NSDictionary *(double start, double end, NSError **error) {
            double a = start ?: 1000, b = end ?: 1335;
            double ratio = (b - a) / 335;
            NSMutableArray *buckets = [NSMutableArray new];
            for (double t = a; t < b; t += 60)
                [buckets addObject:@{
                    @"start" : @(t),
                    @"end" : @(MIN(t + 60, b)),
                    @"ScreenOn" : @(MIN(60, b - t) * 0.9),
                    @"ScreenOff" : @(MIN(60, b - t) * 0.06)
                }];
            NSDictionary *capture = @{
                @"available" : @YES,
                @"source_healthy" : @YES,
                @"observed_wall_time" : @(NSDate.date.timeIntervalSince1970),
                @"checkpoint_native_time" : @1400,
                @"window" :
                    @{@"start" : @1000, @"end" : @1335, @"effective_end" : @1335, @"power_complete" : @YES},
                @"range" : @{@"start" : @(a), @"end" : @(b)},
                @"apps" : @{
                    @"Sample App" : @{@"ScreenOnTime" : @(200 * ratio), @"BackgroundTime" : @(10 * ratio)},
                    @"Messages" : @{@"ScreenOnTime" : @(100 * ratio), @"BackgroundTime" : @(5 * ratio)},
                    @"system.task" : @{@"BackgroundTime" : @(3 * ratio)}
                },
                @"global_metrics" : @{@"ScreenOn" : @(302 * ratio), @"ScreenOff" : @(21 * ratio)},
                @"activity_buckets" : buckets,
                @"activity_latest_end" : @(b),
                @"boundary_interval_count" : @2
            };
            NSArray *displayPoints =
                b >= 1302 ? @[ @{@"time" : @1000,
                                 @"active" : @1},
                               @{@"time" : @1302,
                                 @"active" : @0} ]
                          : @[
                                @{@"time" : @1000,
                                  @"active" : @1}
                            ];
            NSDictionary *source = @{
                @"display_points" : displayPoints,
                @"rows" : @[
                    @{
                        @"ID" : @1,
                        @"timestamp" : @1000,
                        @"StartOffset" : @0,
                        @"EndOffset" : @335000,
                        @"Energy" : @200,
                        @"CorrectionEnergy" : @0,
                        @"TerminationRatio" : @100,
                        @"NodeID" : @1,
                        @"RootNodeID" : @1
                    },
                    @{
                        @"ID" : @2,
                        @"timestamp" : @1000,
                        @"StartOffset" : @0,
                        @"EndOffset" : @335000,
                        @"Energy" : @100,
                        @"CorrectionEnergy" : @0,
                        @"TerminationRatio" : @100,
                        @"NodeID" : @2,
                        @"RootNodeID" : @2
                    }
                ],
                @"node_names" : @{@1 : @"Sample App", @2 : @"Messages"},
                @"levels" : @[ @{@"time" : @(a),
                                 @"level" : @80},
                               @{@"time" : @(b),
                                 @"level" : @79} ]
            };
            return IEBStatisticsModel(capture, source, error);
        }
        catalogProvider:^NSDictionary *(NSArray *identities) {
            (void)identities;
            UIImage *icon = [UIImage systemImageNamed:@"app.fill"];
            return @{
                @"Sample App" : @{@"name" : @"Sample App", @"icon" : icon, @"user_facing" : @YES},
                @"Messages" :
                    @{@"name" : IEBLocalized(@"MESSAGES", @"Messages"), @"icon" : icon, @"user_facing" : @YES}
            };
        }];
    controller.title = IEBLocalized(@"SINCE_UNPLUGGED", @"Since Unplugged");
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:controller];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *dir =
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            (void)ctx;
            [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        }];
        [UIImagePNGRepresentation(image) writeToFile:[dir stringByAppendingPathComponent:@"preview.png"]
                                          atomically:YES];
        NSString *expectedLanguage = [NSUserDefaults.standardUserDefaults stringForKey:@"IEBPreviewLanguage"];
        NSString *expectedAppearance =
            [NSUserDefaults.standardUserDefaults stringForKey:@"IEBPreviewAppearance"];
        BOOL rtl =
            [NSLocale characterDirectionForLanguage:expectedLanguage] == NSLocaleLanguageDirectionRightToLeft;
        NSString *expectedTitle = [NSUserDefaults.standardUserDefaults stringForKey:@"IEBPreviewTitle"];
        UIUserInterfaceStyle expectedStyle =
            [expectedAppearance isEqual:@"dark"] ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        NSMutableDictionary *qa = [@{
            @"language" : expectedLanguage ?: @"",
            @"appearance" : expectedAppearance ?: @"",
            @"language_selected" : @([IEBCurrentLanguage() isEqual:expectedLanguage] &&
                                     [controller.title isEqual:expectedTitle]),
            @"appearance_selected" : @(self.window.traitCollection.userInterfaceStyle == expectedStyle),
            @"panel_rebound" : @(PanelQA()),
            @"sections" : @([controller numberOfSectionsInTableView:controller.tableView]),
            @"quality_and_report" : @(ReportPresentationQA()),
            @"unavailable_diagnostics" : @(UnavailableDiagnosticsQA()),
            @"summary_rows" : @([controller tableView:controller.tableView numberOfRowsInSection:0]),
            @"app_rows" : @([controller tableView:controller.tableView numberOfRowsInSection:3]),
            @"categories" : @([controller numberOfSectionsInTableView:controller.tableView] == 7 &&
                              [controller tableView:controller.tableView numberOfRowsInSection:4] == 1),
            @"app_icon" : @YES
        } mutableCopy];
        UITableViewCell *firstRow = [controller tableView:controller.tableView
                                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]],
                        *secondRow = [controller tableView:controller.tableView
                                     cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:3]];
        firstRow.frame = CGRectMake(0, 0, 390, 130);
        secondRow.frame = firstRow.frame;
        [firstRow layoutIfNeeded];
        [secondRow layoutIfNeeded];
        UIImageView *actualIcon = [firstRow respondsToSelector:NSSelectorFromString(@"sourceIcon")]
                                      ? [firstRow valueForKey:@"sourceIcon"]
                                      : firstRow.imageView;
        qa[@"app_icon"] = @(actualIcon.image != nil);
        UILabel *firstPercent = [firstRow respondsToSelector:NSSelectorFromString(@"percentLabel")]
                                    ? [firstRow valueForKey:@"percentLabel"]
                                    : nil;
        UILabel *secondPercent = [secondRow respondsToSelector:NSSelectorFromString(@"percentLabel")]
                                     ? [secondRow valueForKey:@"percentLabel"]
                                     : nil;
        CGRect p1 = [firstPercent convertRect:firstPercent.bounds toView:firstRow.contentView],
               p2 = [secondPercent convertRect:secondPercent.bounds toView:secondRow.contentView];
        qa[@"percent_column"] =
            @(firstPercent && secondPercent && fabs(p1.origin.x - p2.origin.x) < 1 &&
              fabs(p1.size.width - p2.size.width) < 1 &&
              firstPercent.semanticContentAttribute == UISemanticContentAttributeForceLeftToRight);
        CGRect iconRect = [actualIcon convertRect:actualIcon.bounds toView:firstRow.contentView];
        UISemanticContentAttribute expectedDirection =
            rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
        qa[@"layout_direction"] = @(firstRow.contentView.semanticContentAttribute == expectedDirection &&
                                    firstRow.contentView.effectiveUserInterfaceLayoutDirection ==
                                        (rtl ? UIUserInterfaceLayoutDirectionRightToLeft
                                             : UIUserInterfaceLayoutDirectionLeftToRight) &&
                                    (rtl ? CGRectGetMidX(iconRect) > CGRectGetMidX(p1)
                                         : CGRectGetMidX(iconRect) < CGRectGetMidX(p1)));
        NSString *summary = [controller tableView:controller.tableView
                                cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]]
                                .detailTextLabel.text;
        qa[@"clear_duration"] = @([summary rangeOfString:@"←"].location == NSNotFound &&
                                  [summary rangeOfString:@"→"].location == NSNotFound &&
                                  [summary rangeOfString:@"[0-9]{2}:[0-9]{2}:[0-9]{2}"
                                                 options:NSRegularExpressionSearch]
                                          .location != NSNotFound);
        UITableViewCell *system = [controller tableView:controller.tableView
                                  cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]];
        qa[@"missing_percent_explained"] =
            @([RowLabel(system, @"nameLabel", system.textLabel).text isEqual:@"system.task"] &&
              [RowLabel(system, @"timesLabel", system.detailTextLabel).text
                  containsString:IEBLocalized(@"NO_ENERGY_ATTRIBUTION_IN_THE_SELECTED_RANGE",
                                              @"No energy attribution in the selected range")]);
        UITableViewCell *activity = [controller tableView:controller.tableView
                                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        UIView *chart = activity.contentView.subviews.lastObject;
        ChartTap(chart, 1090);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSDictionary *model = [controller valueForKey:@"model"];
            qa[@"selection"] = @([model[@"range"][@"start"] doubleValue] == 1060 &&
                                 [model[@"range"][@"end"] doubleValue] == 1120 &&
                                 fabs([model[@"screen_on"] doubleValue] - 60) < 0.001 &&
                                 [controller tableView:controller.tableView numberOfRowsInSection:2] == 2);
            UITableViewCell *nextCell = [controller tableView:controller.tableView
                                        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
            UIView *nextChart = nextCell.contentView.subviews.lastObject;
            qa[@"overview_retained"] = @([[nextChart valueForKey:@"points"] count] == 6 &&
                                         [[nextChart valueForKey:@"start"] doubleValue] == 1000 &&
                                         [[nextChart valueForKey:@"end"] doubleValue] == 1335);
            ChartTap(nextChart, 1270);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSDictionary *second = [controller valueForKey:@"model"];
                qa[@"repeat_chart_tap"] = @([second[@"range"][@"start"] doubleValue] == 1240 &&
                                            [second[@"range"][@"end"] doubleValue] == 1300);
                UITableViewCell *levelCell = [controller tableView:controller.tableView
                                             cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0
                                                                                      inSection:1]];
                ChartTap(levelCell.contentView.subviews.lastObject, 1030);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    NSDictionary *third = [controller valueForKey:@"model"];
                    qa[@"level_chart_tap"] = @([third[@"range"][@"start"] doubleValue] == 1000 &&
                                               [third[@"range"][@"end"] doubleValue] == 1060);
                    [controller tableView:controller.tableView
                        didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
                });
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSDictionary *full = [controller valueForKey:@"model"];
                qa[@"reset"] = @([full[@"range"][@"start"] doubleValue] == 1000 &&
                                 [full[@"range"][@"end"] doubleValue] == 1335);
                [controller.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]
                                            atScrollPosition:UITableViewScrollPositionMiddle
                                                    animated:NO];
                UIImage *list = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                    (void)ctx;
                    [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
                }];
                [UIImagePNGRepresentation(list) writeToFile:[dir stringByAppendingPathComponent:@"apps.png"]
                                                 atomically:YES];
                [controller tableView:controller.tableView
                    didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    UITableViewController *details =
                        (UITableViewController *)controller.navigationController.topViewController;
                    [details.tableView layoutIfNeeded];
                    BOOL detailValuesFit = YES;
                    for (UITableViewCell *cell in details.tableView.visibleCells) {
                        UILabel *value = cell.detailTextLabel;
                        if (!value.text.length)
                            continue;
                        CGSize needed = [value.text sizeWithAttributes:@{NSFontAttributeName : value.font}];
                        detailValuesFit &= value.bounds.size.width + 1 >= needed.width;
                    }
                    qa[@"details"] = @(details != controller &&
                                       [details.tableView numberOfRowsInSection:0] == 7 && detailValuesFit);
                    UIImage *detailImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                        (void)ctx;
                        [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
                    }];
                    [UIImagePNGRepresentation(detailImage)
                        writeToFile:[dir stringByAppendingPathComponent:@"details.png"]
                         atomically:YES];
                    RefreshQA(^(BOOL success) {
                        qa[@"refresh_coalesced"] = @(success);
                        UIViewController *owner = [UIViewController new];
                        HeaderFixture *nativeSource = [HeaderFixture new];
                        UITableView *native = HeaderTable(owner, nativeSource, YES);
                        [controller.navigationController pushViewController:owner animated:NO];
                        owner.title = IEBLocalized(@"BATTERY", @"Battery");
                        UISegmentedControl *nativeRanges = nativeSource.range;
                        IEBStatisticsController *panel = [[IEBStatisticsController alloc]
                             initWithLoader:[controller valueForKey:@"loader"]
                            catalogProvider:[controller valueForKey:@"catalogProvider"]];
                        IEBShowSettingsPanel(owner, nativeRanges, panel, ^(NSInteger range) {
                            (void)range;
                            IEBDismissSettingsPanel(owner);
                        });
                        dispatch_after(
                            dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                IEBLayoutSettingsPanel(owner);
                                UIImage *normal =
                                    [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                                        (void)ctx;
                                        [self.window drawViewHierarchyInRect:self.window.bounds
                                                          afterScreenUpdates:YES];
                                    }];
                                [UIImagePNGRepresentation(normal)
                                    writeToFile:[dir stringByAppendingPathComponent:@"panel.png"]
                                     atomically:YES];
                                CGFloat height = panel.view.bounds.size.height;
                                native.scrollEnabled = YES;
                                native.contentOffset = CGPointMake(0, 500);
                                IEBRebindSettingsPanel(owner, nativeRanges);
                                qa[@"panel_scroll_stable"] =
                                    @(native.scrollEnabled && !panel.tableView.scrollEnabled &&
                                      fabs(panel.view.bounds.size.height - height) < 1 &&
                                      native.tableFooterView == panel.view &&
                                      [native numberOfSections] == 2 && nativeSource == native.delegate);
                                UIImage *scrolled =
                                    [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                                        (void)ctx;
                                        [self.window drawViewHierarchyInRect:self.window.bounds
                                                          afterScreenUpdates:YES];
                                    }];
                                [UIImagePNGRepresentation(scrolled)
                                    writeToFile:[dir stringByAppendingPathComponent:@"panel-scrolled.png"]
                                     atomically:YES];
                                CycleQA(^(BOOL good) {
                                    qa[@"cycle_reset"] = @(good);
                                    qa[@"native_chart_host"] = @(NativeChartQA());
                                    qa[@"native_spacing"] = NativeSpacingMeasurements ?: @{};
                                    LiveProcessesQA(^(BOOL passed) {
                                        qa[@"live_processes"] = @(passed);
                                        HistoryQA(^(BOOL history) {
                                            qa[@"cycle_history"] = @(history);
                                            [qa writeToFile:[dir stringByAppendingPathComponent:@"qa.plist"]
                                                 atomically:YES];
                                        });
                                    });
                                });
                            });
                    });
                });
            });
        });
    });
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PreviewDelegate.class));
    }
}
