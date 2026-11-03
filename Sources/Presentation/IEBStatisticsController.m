#import "IEBStatisticsController.h"
#import "../Diagnostics/IEBDiagnosticExport.h"
#import "../Diagnostics/IEBDiagnosticReport.h"
#import "../Diagnostics/IEBProcessAttribution.h"
#import "../Diagnostics/IEBProcessSnapshot.h"
#import "../Diagnostics/IEBRootProcessClient.h"
#import "../Statistics/IEBCycleHistory.h"
#import "../Statistics/IEBDataQuality.h"
#import "../Statistics/IEBSourceGroups.h"
#import "IEBApplicationCatalog.h"
#import "IEBCycleHistoryController.h"
#import "IEBNativeBatteryCells.h"
#import "IEBNativeChartController.h"
#import "IEBProcessesController.h"
#import "IEBSourceCell.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *IEBDuration(id value) {
    if (![value isKindOfClass:NSNumber.class])
        return @"—";
    double seconds = [value doubleValue];
    if (!isfinite(seconds) || seconds < 0 || seconds > 86400000)
        return @"—";
    NSInteger s = (NSInteger)round(seconds);
    return [NSString
        stringWithFormat:@"%02ld:%02ld:%02ld", (long)(s / 3600), (long)(s / 60 % 60), (long)(s % 60)];
}
static NSString *Percent(id value) {
    return [value isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%.1f%%", [value doubleValue]]
                                                : @"—";
}
static double ChartValue(id value) { return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0; }
@interface IEBChart : UIView
@property(nonatomic, copy) NSArray *points, *selectionBuckets;
@property(nonatomic) BOOL activity;
@property(nonatomic) double start, end, selectedStart, selectedEnd;
@property(nonatomic, copy) void (^selection)(NSDictionary *bucket);
@end
@implementation IEBChart
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.isAccessibilityElement = YES;
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(tap:)]];
    }
    return self;
}
- (void)tap:(UITapGestureRecognizer *)tap {
    if (!self.selection || !self.selectionBuckets.count || self.end <= self.start)
        return;
    CGPoint point = [tap locationInView:self];
    CGFloat width = self.bounds.size.width - 47;
    if (width <= 0 || point.x < 35 || point.x > 35 + width || point.y < 10 ||
        point.y > self.bounds.size.height - 25)
        return;
    double time = self.start + (point.x - 35) / width * (self.end - self.start);
    for (NSDictionary *bucket in self.selectionBuckets) {
        if (time >= [bucket[@"start"] doubleValue] &&
            (time < [bucket[@"end"] doubleValue] ||
             (bucket == self.selectionBuckets.lastObject && time <= self.end))) {
            self.selection(bucket);
            return;
        }
    }
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width - 47, h = self.bounds.size.height - 35, left = 35, top = 10;
    if (w <= 0 || h <= 0)
        return;
    NSDictionary *attrs = @{
        NSFontAttributeName : [UIFont systemFontOfSize:10],
        NSForegroundColorAttributeName : UIColor.secondaryLabelColor
    };
    CGContextSetStrokeColorWithColor(ctx, UIColor.separatorColor.CGColor);
    CGContextSetLineWidth(ctx, 0.5);
    for (int i = 0; i <= 4; i++) {
        CGFloat y = top + h * i / 4;
        CGContextMoveToPoint(ctx, left, y);
        CGContextAddLineToPoint(ctx, left + w, y);
        CGContextStrokePath(ctx);
        if (!self.activity)
            [[NSString stringWithFormat:@"%d", 100 - i * 25] drawAtPoint:CGPointMake(3, y - 5)
                                                          withAttributes:attrs];
    }
    if (self.activity) {
        double maximum = 60;
        for (NSDictionary *p in self.points)
            maximum = MAX(maximum, MAX([p[@"end"] doubleValue] - [p[@"start"] doubleValue],
                                       ChartValue(p[@"ScreenOn"]) + ChartValue(p[@"ScreenOff"])));
        [[NSString stringWithFormat:@"%.0fm", maximum / 60] drawAtPoint:CGPointMake(1, top)
                                                         withAttributes:attrs];
        for (NSUInteger i = 0; i < self.points.count; i++) {
            NSDictionary *p = self.points[i];
            CGFloat on = h * ChartValue(p[@"ScreenOn"]) / maximum,
                    off = h * ChartValue(p[@"ScreenOff"]) / maximum;
            CGFloat x =
                left + w * ([p[@"start"] doubleValue] - self.start) / MAX(0.001, self.end - self.start);
            CGFloat width =
                w * ([p[@"end"] doubleValue] - [p[@"start"] doubleValue]) / MAX(0.001, self.end - self.start);
            [UIColor.systemGreenColor setFill];
            CGContextFillRect(ctx, CGRectMake(x + 1, top + h - on, MAX(1, width - 2), on));
            [UIColor.systemBlueColor setFill];
            CGContextFillRect(ctx, CGRectMake(x + 1, top + h - on - off, MAX(1, width - 2), off));
            if (p[@"ScreenOn"] == NSNull.null || p[@"ScreenOff"] == NSNull.null) {
                [UIColor.systemGrayColor setFill];
                CGContextFillRect(ctx,
                                  CGRectMake(x + 1, MAX(top, top + h - on - off - 4), MAX(1, width - 2), 4));
            }
        }
    } else {
        UIBezierPath *path = [UIBezierPath bezierPath];
        BOOL first = YES;
        for (NSDictionary *p in self.points) {
            CGFloat x = left + w * MAX(0, MIN(1, ([p[@"time"] doubleValue] - self.start) /
                                                     MAX(0.001, self.end - self.start)));
            CGFloat y = top + h * (100 - [p[@"level"] doubleValue]) / 100;
            if (first)
                [path moveToPoint:CGPointMake(x, y)];
            else
                [path addLineToPoint:CGPointMake(x, y)];
            first = NO;
            if (self.points.count == 1) {
                [UIColor.systemGreenColor setFill];
                CGContextFillEllipseInRect(ctx, CGRectMake(x - 3, y - 3, 6, 6));
            }
        }
        [UIColor.systemGreenColor setStroke];
        path.lineWidth = 2;
        [path stroke];
    }
    if (self.selectedStart > 0 && self.selectedEnd > self.selectedStart) {
        CGFloat x = left + w * (self.selectedStart - self.start) / MAX(0.001, self.end - self.start);
        CGFloat width = w * (self.selectedEnd - self.selectedStart) / MAX(0.001, self.end - self.start);
        CGContextSetStrokeColorWithColor(ctx, UIColor.systemOrangeColor.CGColor);
        CGContextSetLineWidth(ctx, 2);
        CGContextStrokeRect(ctx, CGRectMake(x + 1, top + 1, MAX(1, width - 2), h - 2));
    }
    [@"0" drawAtPoint:CGPointMake(left, top + h + 5) withAttributes:attrs];
    [IEBDuration(@(self.end - self.start)) drawAtPoint:CGPointMake(MAX(left, left + w - 70), top + h + 5)
                                        withAttributes:attrs];
}
@end
@interface IEBDetails : UITableViewController
@property(nonatomic, copy) NSArray *rows;
@end
@implementation IEBDetails
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return IEBLocalized(@"PROCESS_ACTIVITY_AND_AUDIO_ARE_SEPARATE_OVERLAPPING_MEASUREMENTS_AUDIO_MAY_",
                        @"Process activity and audio are separate, overlapping measurements. Audio may "
                        @"include playback while the app is on screen. These durations must not be added.");
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)self.rows.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.textLabel.text = self.rows[(NSUInteger)index.row][0];
    cell.detailTextLabel.text = self.rows[(NSUInteger)index.row][1];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}
@end
@interface IEBStatisticsController ()
@property(nonatomic, copy) NSDictionary * (^loader)(double, double, NSError **);
@property(nonatomic, strong) NSDictionary *model, *overviewModel;
@property(nonatomic, strong) IEBNativeChartController *nativeCharts;
@property(nonatomic, strong) NSDictionary *processSnapshot, *processSources;
@property(nonatomic) BOOL nativeChartReady;
@property(nonatomic, copy) NSDictionary * (^catalogProvider)(NSArray<NSString *> *);
@property(nonatomic, copy) NSDictionary *catalog;
@property(nonatomic, copy) NSDictionary *groups;
@property(nonatomic, strong) NSError *loadError;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) double selectedStart, selectedEnd, selectedCycleStart;
@property(nonatomic) BOOL active, loading, refreshPending, catalogUnavailable;
@end
@implementation IEBStatisticsController
@synthesize nativeTablePresentation = _nativeTablePresentation;
- (void)setNativeTablePresentation:(BOOL)nativeTablePresentation {
    if (_nativeTablePresentation == nativeTablePresentation)
        return;
    _nativeTablePresentation = nativeTablePresentation;
    if (self.isViewLoaded) {
        self.tableView.tableHeaderView =
            nativeTablePresentation ? [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 0.01)] : nil;
        [self.tableView reloadData];
    }
}
- (instancetype)initWithLoader:(NSDictionary * (^)(double, double, NSError **))loader
               catalogProvider:(NSDictionary * (^)(NSArray<NSString *> *))provider {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _loader = [loader copy];
        _catalogProvider = [provider copy];
        _queue = dispatch_queue_create("com.idonamaan.ieb.settings-loader", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (instancetype)initWithLoader:(NSDictionary * (^)(double, double, NSError **))loader {
    return [self initWithLoader:loader
                catalogProvider:^NSDictionary *(NSArray *identities) {
                    return IEBLoadApplicationCatalog(identities);
                }];
}
- (void)beginNativeTablePresentationInOwner:(UIViewController *)owner {
    [self loadViewIfNeeded];
    if (!self.nativeTablePresentation || !self.nativeCharts ||
        self.nativeCharts.parentViewController == owner)
        return;
    [self.nativeCharts willMoveToParentViewController:nil];
    [self.nativeCharts.view removeFromSuperview];
    [self.nativeCharts removeFromParentViewController];
    [owner addChildViewController:self.nativeCharts];
    [self.nativeCharts didMoveToParentViewController:owner];
}
- (void)endNativeTablePresentation {
    IEBRestoreNativeChartView(self.nativeCharts.view);
    if (!self.nativeCharts || self.nativeCharts.parentViewController == self)
        return;
    [self.nativeCharts willMoveToParentViewController:nil];
    [self.nativeCharts.view removeFromSuperview];
    [self.nativeCharts removeFromParentViewController];
    [self addChildViewController:self.nativeCharts];
    [self.nativeCharts didMoveToParentViewController:self];
}
- (UIView *)nativeChartView {
    [self loadViewIfNeeded];
    return self.nativeCharts.view;
}
- (void)updateNativeTimeUsageCell:(UITableViewCell *)cell {
    IEBApplyNativeTimeUsage(cell, self.model[@"screen_on"], self.model[@"screen_off"]);
}
- (NSArray *)rowsForSection:(NSInteger)section {
    return self.groups[section == 3 ? @"applications" : @"system_processes"] ?: @[];
}
- (NSString *)nameForIdentity:(NSString *)identity {
    return self.catalog[identity][@"name"]
               ?: ([identity hasPrefix:@"IEB.Unknown."]
                       ? IEBLocalized(@"UNIDENTIFIED_SYSTEM_SOURCE", @"Unidentified system source")
                       : identity);
}
- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    self.nativeCharts = [[IEBNativeChartController alloc] initWithSelection:^(NSDictionary *range) {
        typeof(self) strong = weakSelf;
        if (!strong)
            return;
        BOOL same = range && strong.selectedStart == [range[@"start"] doubleValue] &&
                    strong.selectedEnd == [range[@"end"] doubleValue];
        strong.selectedStart = same ? 0 : [range[@"start"] doubleValue];
        strong.selectedEnd = same ? 0 : [range[@"end"] doubleValue];
        strong.selectedCycleStart =
            strong.selectedStart ? [strong.overviewModel[@"window"][@"start"] doubleValue] : 0;
        [strong refresh];
    }];
    if (self.nativeCharts) {
        self.nativeCharts.presentation = self.nativeChartPresentation;
        [self addChildViewController:self.nativeCharts];
        [self.nativeCharts didMoveToParentViewController:self];
    }
    if (self.nativeTablePresentation)
        self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 0.01)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self
                            action:@selector(refresh)
                  forControlEvents:UIControlEventValueChanged];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.active = YES;
    [self refresh];
    __weak typeof(self) weak = self;
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5
                                                 repeats:YES
                                                   block:^(NSTimer *timer) {
                                                       (void)timer;
                                                       [weak refresh];
                                                   }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.active = NO;
    self.generation++;
    [self.timer invalidate];
    self.timer = nil;
}
- (void)refresh {
    if (!self.active)
        return;
    if (self.loading) {
        self.refreshPending = YES;
        return;
    }
    self.loading = YES;
    self.refreshPending = NO;
    NSUInteger generation = ++self.generation;
    double start = self.selectedStart, end = self.selectedEnd, cycle = self.selectedCycleStart;
    NSDictionary * (^loader)(double, double, NSError **) = [self.loader copy];
    NSDictionary * (^provider)(NSArray *) = [self.catalogProvider copy];
    __weak typeof(self) weak = self;
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSDictionary *overview = loader(0, 0, &error);
        NSDictionary *model = overview;
        BOOL invalidSelection =
            start > 0 && (!overview || cycle != [overview[@"window"][@"start"] doubleValue] ||
                          start < [overview[@"range"][@"start"] doubleValue] ||
                          end > [overview[@"range"][@"end"] doubleValue]);
        if (start > 0 && !invalidSelection) {
            model = loader(start, end, &error);
            if (!model ||
                [model[@"window"][@"start"] doubleValue] != [overview[@"window"][@"start"] doubleValue]) {
                model = overview;
                invalidSelection = YES;
            }
        }
        if (invalidSelection && model)
            error = nil;
        NSArray *identities = [model[@"apps"] valueForKey:@"id"] ?: @[];
        NSDictionary *resolved = provider(identities);
        NSDictionary *catalog = resolved ?: @{};
        NSDictionary *groups = IEBSourceGroups(model[@"apps"] ?: @[], catalog);
        NSDictionary *processSnapshot = IEBReadPreferredProcessSnapshot();
        NSDictionary *processJoin =
            IEBProcessAttribution(model[@"apps"] ?: @[], catalog, processSnapshot, nil);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strong = weak;
            if (!strong)
                return;
            strong.loading = NO;
            if (!strong.active) {
                strong.refreshPending = NO;
                return;
            }
            if (generation != strong.generation || start != strong.selectedStart ||
                end != strong.selectedEnd) {
                [strong refresh];
                return;
            }
            if (invalidSelection) {
                strong.selectedStart = 0;
                strong.selectedEnd = 0;
                strong.selectedCycleStart = 0;
            }
            strong.overviewModel = overview;
            strong.processSnapshot = processSnapshot;
            strong.processSources = processJoin[@"sources"];
            NSDictionary *presentation =
                strong.nativeChartPresentationProvider ? strong.nativeChartPresentationProvider() : nil;
            if (presentation) {
                strong.nativeChartPresentation = presentation;
                strong.nativeCharts.presentation = presentation;
            }
            strong.nativeChartReady = [strong.nativeCharts configureOverview:overview
                                                               selectedStart:strong.selectedStart
                                                                 selectedEnd:strong.selectedEnd];
            strong.model = model;
            if (strong.nativePresentationDidUpdate)
                strong.nativePresentationDidUpdate();
            strong.catalog = catalog;
            strong.groups = groups;
            strong.catalogUnavailable = resolved == nil;
            strong.loadError = error;
            [strong.refreshControl endRefreshing];
            [strong.tableView reloadData];
            if (strong.refreshPending)
                [strong refresh];
        });
    });
}
- (NSInteger)logicalSection:(NSInteger)section {
    if (!self.model || [self.model[@"state"] isEqual:@"waiting"])
        return section == 1 ? 6 : (self.nativeTablePresentation ? 5 : 0);
    if (!self.nativeTablePresentation)
        return section;
    return section + 3;
}
- (NSIndexPath *)logicalIndexPath:(NSIndexPath *)path {
    return [NSIndexPath indexPathForRow:path.row inSection:[self logicalSection:path.section]];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    BOOL ready = self.model && ![self.model[@"state"] isEqual:@"waiting"];
    return ready ? (self.nativeTablePresentation ? 4 : 7) : 2;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    section = [self logicalSection:section];
    if (section == 6)
        return 3;
    if (!self.model || [self.model[@"state"] isEqual:@"waiting"])
        return 1;
    if (self.nativeTablePresentation && section == 5)
        return 2;
    if (section == 0)
        return 3;
    if (section == 2)
        return self.nativeCharts ? (self.selectedStart > 0 ? 1 : 0) : (self.selectedStart > 0 ? 2 : 1);
    if (section == 3 || section == 4)
        return (NSInteger)[[self rowsForSection:section] count];
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    section = [self logicalSection:section];
    if (section == 3) {
        NSDictionary *quality = IEBDataQuality(self.model);
        NSString *state =
            [quality[@"state"] isEqual:@"recorded"]
                ? IEBLocalized(@"LATEST_GLOBAL_ACTIVITY_RECORDED", @"Latest global activity recorded")
                : IEBLocalized(@"PARTIAL_STATISTICS_TOTALS_MAY_CHANGE",
                               @"Partial statistics · totals may change");
        NSString *activity = [NSString
            stringWithFormat:IEBLocalized(@"ACTIVITY_RECORDED_THROUGH_FROM_RANGE_START_PENDING",
                                          @"Activity recorded through %@ from range start · pending %@"),
                             IEBDuration(quality[@"activity_recorded_seconds"]),
                             IEBDuration(quality[@"pending_seconds"])];
        NSString *energy = [quality[@"energy_state"] isEqual:@"recorded"]
                               ? IEBLocalized(@"ENERGY_RECORDS_SPAN_THE_RANGE_APP_COVERAGE_IS_UNVERIFIED",
                                              @"Energy records span the range; app coverage is unverified.")
                           : [quality[@"energy_state"] isEqual:@"partial"]
                               ? IEBLocalized(@"ENERGY_RECORDS_ARE_PARTIAL_OR_COVERAGE_IS_UNKNOWN",
                                              @"Energy records are partial or coverage is unknown.")
                               : IEBLocalized(@"ENERGY_RECORDS_UNAVAILABLE", @"Energy records unavailable.");
        NSString *recovery =
            [quality[@"recovered_cycle"] boolValue]
                ? IEBLocalized(@"RECOVERED_THROUGH_LAST_CHECKPOINT_LATER_TIME_IS_UNKNOWN_RECONNECT_AND_UNPLU",
                               @"\nRecovered through last checkpoint. Later time is unknown; reconnect and "
                               @"unplug to start a new cycle.")
                : @"";
        NSString *levels =
            [quality[@"levels_available"] boolValue]
                ? @""
                : IEBLocalized(@"BATTERY_LEVEL_RECORDS_UNAVAILABLE", @"\nBattery level records unavailable.");
        return [NSString stringWithFormat:@"%@\n%@\n%@%@%@\n\n%@", state, activity, energy, levels, recovery,
                                          IEBLocalized(@"APPLICATIONS", @"Applications")];
    }
    if (self.nativeCharts && (section == 1 || section == 2))
        return nil;
    return @[
        IEBLocalized(@"SINCE_UNPLUGGED", @"Since Unplugged"),
        IEBLocalized(@"BATTERY_LEVEL", @"Battery Level"),
        IEBLocalized(@"ACTIVITY_TAP_A_BAR_TO_SELECT", @"Activity · tap a bar to select"),
        IEBLocalized(@"APPLICATIONS", @"Applications"),
        IEBLocalized(@"BACKGROUND_AND_SYSTEM_PROCESSES", @"Background and System Processes"),
        IEBLocalized(@"ABOUT_THESE_STATISTICS", @"About These Statistics"),
        IEBLocalized(@"PROCESS_DIAGNOSTICS", @"Process Diagnostics")
    ][(NSUInteger)section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    section = [self logicalSection:section];
    if (section == 0 && self.model && ![self.model[@"state"] isEqual:@"waiting"]) {
        double pending = [self.model[@"activity_pending_seconds"] doubleValue];
        return pending > 1
                   ? [NSString
                         stringWithFormat:IEBLocalized(@"WAITING_FOR_THE_SYSTEM_S_LAST_ACTIVITY_RECORD_OF_"
                                                       @"THIS_RANGE_REFRESHES_EVERY",
                                                       @"Waiting for the system's last activity record (%@ "
                                                       @"of this range). Refreshes every 5 seconds."),
                                          IEBDuration(@(pending))]
                   : IEBLocalized(@"REFRESHES_EVERY_5_SECONDS_SYSTEM_ENERGY_ACCOUNTING_CAN_ARRIVE_LATER",
                                  @"Refreshes every 5 seconds. System energy accounting can arrive later.");
    }
    if (self.nativeCharts && section == 1)
        return IEBLocalized(@"ORIGINAL_SYSTEM_CHARTS_AT_MOST_THE_LAST_24_HOURS_OF_THIS_CYCLE_EMPTY_SLOTS_",
                            @"Original system charts · at most the last 24 hours of this cycle. Empty slots "
                            @"are outside the cycle or unavailable. Summary totals cover the entire cycle.");
    if (self.nativeCharts && section == 2)
        return nil;
    if (section == 6)
        return IEBLocalized(
            @"LIVE_CPU_COUNTERS_ARE_SEPARATE_FROM_BACKGROUND_ACTIVITY_AND_RECORDED_BATTER",
            @"Live CPU counters are separate from background activity and recorded battery energy.");
    if (section == 3)
        return IEBLocalized(@"INCLUDES_EACH_APPLICATION_S_BACKGROUND_USAGE_PERCENTAGES_USE_THE_SAME_TOTAL",
                            @"Includes each application's background usage. Percentages use the same total "
                            @"as system processes.");
    if (section == 4)
        return IEBLocalized(
            @"INTERNAL_OR_HIDDEN_SYSTEM_APPS_SERVICES_EXTENSIONS_AND_UNIDENTIFIED_SOURCES",
            @"Internal or hidden system apps, services, extensions and unidentified sources.");
    return section == 2 ? IEBLocalized(@"GREEN_SCREEN_ON_BLUE_SCREEN_OFF_USAGE_GREY_UNAVAILABLE",
                                       @"Green: screen on · Blue: screen off usage · Grey: unavailable")
                        : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self logicalSection:section] == 3) {
        NSString *text = [self tableView:tableView titleForHeaderInSection:section];
        CGRect bounds = [text
            boundingRectWithSize:CGSizeMake(MAX(1, tableView.bounds.size.width - 40), CGFLOAT_MAX)
                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                      attributes:@{
                          NSFontAttributeName : [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]
                      }
                         context:nil];
        return ceil(bounds.size.height) + 24;
    }
    return UITableViewAutomaticDimension;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self logicalSection:section] != 3)
        return nil;
    UIView *view = [UIView new];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.text = [self tableView:tableView titleForHeaderInSection:section];
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-12]
    ]];
    return view;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return UITableViewAutomaticDimension;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index {
    (void)tableView;
    index = [self logicalIndexPath:index];
    if (self.nativeCharts && index.section == 1)
        return self.nativeChartPresentation[@"height"]
                   ? [self.nativeChartPresentation[@"height"] doubleValue]
                   : [IEBNativeChartController heightForTraits:self.traitCollection];
    if (self.nativeCharts && index.section == 2)
        return UITableViewAutomaticDimension;
    return self.model && ![self.model[@"state"] isEqual:@"waiting"] &&
                   (index.section == 1 || (index.section == 2 && index.row == 0))
               ? 165
               : UITableViewAutomaticDimension;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)tableView;
    index = [self logicalIndexPath:index];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (index.section == 6) {
        if (index.row == 2) {
            cell.textLabel.text =
                IEBLocalized(@"SAVED_CYCLES_AND_COMPARISON", @"Saved cycles and comparison");
            cell.detailTextLabel.text = IEBLocalized(@"UP_TO_20_CLOSED_CYCLES_SELECT_TWO_TO_COMPARE",
                                                     @"Up to 20 closed cycles · select two to compare");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        if (index.row == 1) {
            cell.textLabel.text = IEBLocalized(@"EXPORT_DIAGNOSTIC_REPORT", @"Export Diagnostic Report");
            cell.detailTextLabel.text =
                IEBLocalized(@"READABLE_TXT_IN_THE_INTERFACE_LANGUAGE_AND_TECHNICAL_JSON_AGGREGATE_DATA_ON",
                             @"Readable TXT in the interface language and technical JSON · aggregate data "
                             @"only. Choose where to share.");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        cell.textLabel.text = IEBLocalized(@"VIEW_LIVE_PROCESSES", @"View live processes");
        cell.detailTextLabel.text = IEBProcessStatusText(self.processSnapshot);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (!self.model) {
        cell.textLabel.text = self.loadError
                                  ? IEBLocalized(@"BATTERY_STATISTICS_COULD_NOT_BE_READ_PULL_TO_REFRESH",
                                                 @"Battery statistics could not be read. Pull to refresh.")
                                  : IEBLocalized(@"LOADING", @"Loading…");
        return cell;
    }
    if ([self.model[@"state"] isEqual:@"waiting"]) {
        cell.textLabel.text =
            IEBLocalized(@"WAITING_FOR_AN_OBSERVED_UNPLUG_CYCLE", @"Waiting for an observed unplug cycle.");
        return cell;
    }
    if (self.nativeCharts && index.section == 1) {
        if (!self.nativeChartReady) {
            cell.textLabel.text =
                IEBLocalized(@"ORIGINAL_CHART_DATA_UNAVAILABLE", @"Original chart data unavailable");
            return cell;
        }
        return [self.nativeCharts makeChartCell];
    }
    if (self.nativeCharts && index.section == 2) {
        cell.textLabel.text = IEBLocalized(@"SHOW_ENTIRE_CYCLE", @"Show Entire Cycle");
        cell.textLabel.textColor = UIColor.linkColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (index.section == 0 || (self.nativeTablePresentation && index.section == 5 && index.row == 0)) {
        if (index.row == 0) {
            NSDictionary *range = self.model[@"range"], *window = self.model[@"window"];
            cell.textLabel.text =
                [self.model[@"state"] isEqual:@"incomplete"]
                    ? IEBLocalized(@"INCOMPLETE_CAPTURE", @"Incomplete capture")
                : window[@"end"] ? IEBLocalized(@"LAST_CYCLE_RECONNECTED", @"Last cycle · reconnected")
                                 : IEBLocalized(@"CURRENT_CYCLE_ON_BATTERY", @"Current cycle · on battery");
            NSString *duration = IEBDuration(@([range[@"end"] doubleValue] - [range[@"start"] doubleValue]));
            if (self.selectedStart > 0) {
                cell.detailTextLabel.text = [NSString
                    stringWithFormat:IEBLocalized(
                                         @"SELECTED_FROM_TO_AFTER_UNPLUG_RANGE_DURATION",
                                         @"Selected: from %@ to %@ after unplug\nRange duration: %@"),
                                     IEBDuration(
                                         @([range[@"start"] doubleValue] - [window[@"start"] doubleValue])),
                                     IEBDuration(
                                         @([range[@"end"] doubleValue] - [window[@"start"] doubleValue])),
                                     duration];
            } else {
                cell.detailTextLabel.text = [NSString
                    stringWithFormat:IEBLocalized(@"CYCLE_DURATION", @"Cycle duration: %@"), duration];
            }
            if ([self.model[@"state"] isEqual:@"incomplete"])
                cell.textLabel.textColor = UIColor.systemOrangeColor;
        } else {
            cell.textLabel.text = index.row == 1 ? IEBLocalized(@"SCREEN_ON", @"Screen On")
                                                 : IEBLocalized(@"SCREEN_OFF_USAGE", @"Screen Off Usage");
            cell.detailTextLabel.text =
                IEBDuration(self.model[index.row == 1 ? @"screen_on" : @"screen_off"]);
        }
    } else if (index.section == 1 || (index.section == 2 && index.row == 0)) {
        BOOL activity = index.section == 2;
        NSDictionary *overview = self.overviewModel ?: self.model;
        NSArray *points = overview[activity ? @"activity_buckets" : @"levels"];
        if (!points.count) {
            cell.textLabel.text = IEBLocalized(@"DATA_UNAVAILABLE", @"Data unavailable");
            return cell;
        }
        IEBChart *chart =
            [[IEBChart alloc] initWithFrame:CGRectMake(8, 4, cell.contentView.bounds.size.width - 16, 157)];
        chart.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        chart.points = points;
        chart.activity = activity;
        chart.start = [overview[@"range"][@"start"] doubleValue];
        chart.selectionBuckets = overview[@"activity_buckets"];
        chart.selectedStart = self.selectedStart;
        chart.selectedEnd = self.selectedEnd;
        chart.end = [overview[@"range"][@"end"] doubleValue];
        chart.accessibilityLabel =
            activity ? IEBLocalized(@"ACTIVITY_GRAPH_GREEN_SCREEN_ON_BLUE_SCREEN_OFF_USAGE",
                                    @"Activity graph. Green: screen on. Blue: screen off usage.")
                     : IEBLocalized(@"BATTERY_LEVEL_GRAPH", @"Battery level graph");
        __weak typeof(self) weak = self;
        chart.selection = ^(NSDictionary *bucket) {
            BOOL same = weak.selectedStart == [bucket[@"start"] doubleValue] &&
                        weak.selectedEnd == [bucket[@"end"] doubleValue];
            weak.selectedCycleStart = same ? 0 : [weak.overviewModel[@"window"][@"start"] doubleValue];
            weak.selectedStart = same ? 0 : [bucket[@"start"] doubleValue];
            weak.selectedEnd = same ? 0 : [bucket[@"end"] doubleValue];
            [weak refresh];
        };
        [cell.contentView addSubview:chart];
    } else if (index.section == 2) {
        cell.textLabel.text = IEBLocalized(@"SHOW_ENTIRE_CYCLE", @"Show Entire Cycle");
        cell.textLabel.textColor = UIColor.linkColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (index.section == 3 || index.section == 4) {
        NSDictionary *row = [self rowsForSection:index.section][(NSUInteger)index.row];
        IEBSourceCell *sourceCell = [[IEBSourceCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                         reuseIdentifier:nil];
        BOOL hasPercent = [row[@"percent"] isKindOfClass:NSNumber.class];
        NSString *name = [self nameForIdentity:row[@"id"]];
        cell.textLabel.text =
            hasPercent ? [NSString stringWithFormat:@"%@   %@", name, Percent(row[@"percent"])] : name;
        cell.detailTextLabel.text = [NSString
            stringWithFormat:@"%@: %@ · %@: %@", IEBLocalized(@"ON_SCREEN", @"On screen"),
                             IEBDuration(row[@"foreground"]),
                             IEBLocalized(@"PROCESS_BACKGROUND_ACTIVITY", @"Process background activity"),
                             IEBDuration(row[@"background"])];
        if (index.section == 4) {
            NSDictionary *cpu = self.processSources[row[@"id"]];
            NSString *value = cpu ? [NSString stringWithFormat:@"%.2f s", [cpu[@"cpu_seconds"] doubleValue]]
                                  : IEBLocalized(@"UNAVAILABLE_OR_NO_UNIQUE_PROCESS_MATCH",
                                                 @"Unavailable or no unique process match");
            cell.detailTextLabel.text = [cell.detailTextLabel.text
                stringByAppendingFormat:@"\n%@: %@",
                                        IEBLocalized(@"CPU_TIME_CURRENT_PROCESS_LIFETIME",
                                                     @"CPU time · current process lifetime"),
                                        value];
        }
        if (!hasPercent)
            cell.detailTextLabel.text =
                [NSString stringWithFormat:@"%@\n%@",
                                           IEBLocalized(@"NO_ENERGY_ATTRIBUTION_IN_THE_SELECTED_RANGE",
                                                        @"No energy attribution in the selected range"),
                                           cell.detailTextLabel.text];
        [sourceCell configureName:name
                       percentage:hasPercent ? Percent(row[@"percent"]) : nil
                          details:cell.detailTextLabel.text
                             icon:self.catalog[row[@"id"]][@"icon"]];
        return sourceCell;
    } else {
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        cell.textLabel.text =
            IEBLocalized(@"ENERGY_USES_THE_SYSTEM_S_LOGGED_ESTIMATES_BOUNDARY_ACTIVITY_IS_ALLOCATED_PR",
                         @"Energy uses the system's logged estimates. Boundary activity is allocated "
                         @"proportionally. Source grouping may differ from Apple's app list. Delayed records "
                         @"can update totals after reconnecting. — means unavailable, not zero.");
        NSMutableArray *messages = [NSMutableArray new];
        if (self.nativeTablePresentation && !self.nativeChartReady)
            [messages addObject:IEBLocalized(@"CHART_DATA_UNAVAILABLE_STALE_VALUES_ARE_CLEARED",
                                             @"Chart data unavailable; stale values are cleared.")];
        if (self.catalogUnavailable)
            [messages
                addObject:IEBLocalized(
                              @"INSTALLED_APPLICATIONS_COULD_NOT_BE_IDENTIFIED_SOURCES_ARE_LISTED_IN_THE_OT",
                              @"Installed applications could not be identified; sources are listed in the "
                              @"other category.")];
        if (self.model[@"energy_error"] != NSNull.null)
            [messages addObject:IEBLocalized(@"ENERGY_DATA_UNAVAILABLE", @"Energy data unavailable.")];
        if (self.model[@"levels_error"] != NSNull.null)
            [messages addObject:IEBLocalized(@"BATTERY_LEVELS_UNAVAILABLE", @"Battery levels unavailable.")];
        if ([self.model[@"energy_retention_incomplete"] boolValue])
            [messages
                addObject:
                    IEBLocalized(
                        @"ENERGY_RECORDS_COVER_ONLY_PART_OF_THIS_RANGE_ACCOUNTING_MAY_STILL_BE_DELAYE",
                        @"Energy records cover only part of this range; accounting may still be delayed.")];
        cell.detailTextLabel.text = [messages componentsJoinedByString:@"\n"];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    index = [self logicalIndexPath:index];
    if (index.section == 6) {
        if (index.row == 2) {
            IEBCycleHistoryController *history = [[IEBCycleHistoryController alloc]
                initWithListLoader:^NSArray *(NSError **error) {
                    return IEBReadNativeCycleHistory(@"/var/mobile/Library/IEBNativeCapture", error);
                }
                detailLoader:^NSDictionary *(NSDictionary *record, NSError **error) {
                    return IEBLoadHistoricalCycle(record, nil, error);
                }];
            [self.navigationController pushViewController:history animated:YES];
            return;
        }
        if (index.row == 1) {
            [self exportDiagnosticReport];
            return;
        }
        NSDictionary * (^load)(double, double, NSError **) = [self.loader copy];
        NSDictionary * (^catalog)(NSArray *) = [self.catalogProvider copy];
        IEBProcessesController *processes = [[IEBProcessesController alloc] initWithLoader:^NSDictionary * {
            NSError *error = nil;
            NSDictionary *model = load(0, 0, &error);
            NSArray *sources = model[@"apps"] ?: @[];
            return @{
                @"snapshot" : IEBReadPreferredProcessSnapshot(),
                @"sources" : sources,
                @"catalog" : catalog([sources valueForKey:@"id"]) ?: @{}
            };
        }];
        [self.navigationController pushViewController:processes animated:YES];
        return;
    }
    if (index.section == 2 && index.row == (self.nativeCharts ? 0 : 1)) {
        self.selectedStart = 0;
        self.selectedEnd = 0;
        [self refresh];
        return;
    }
    if (index.section != 3 && index.section != 4)
        return;
    NSDictionary *app = [self rowsForSection:index.section][(NSUInteger)index.row];
    NSMutableArray *rows = [NSMutableArray arrayWithArray:@[
        @[
            IEBLocalized(@"RELATIVE_BATTERY_USAGE", @"Relative Battery Usage"),
            [app[@"percent"] isKindOfClass:NSNumber.class]
                ? Percent(app[@"percent"])
                : IEBLocalized(@"NO_ATTRIBUTION_IN_THIS_RANGE", @"No attribution in this range")
        ],
        @[ IEBLocalized(@"ON_SCREEN_2", @"On Screen"), IEBDuration(app[@"foreground"]) ],
        @[
            IEBLocalized(@"PROCESS_BACKGROUND_ACTIVITY", @"Process background activity"),
            IEBDuration(app[@"background"])
        ]
    ]];
    NSArray *categories = @[
        @[ IEBLocalized(@"NOW_PLAYING", @"Now Playing"), @"audio_now_playing" ],
        @[
            IEBLocalized(@"AUDIO_PLAYBACK_SEPARATE_MEASUREMENT", @"Audio playback · separate measurement"),
            @"audio_playback"
        ],
        @[ IEBLocalized(@"LOCATION", @"Location"), @"location" ],
        @[ IEBLocalized(@"LOCATION_AND_AUDIO", @"Location and Audio"), @"location_audio" ]
    ];
    for (NSArray *category in categories)
        [rows addObject:@[ category[0], IEBDuration(app[category[1]] ?: NSNull.null) ]];
    IEBDetails *details = [[IEBDetails alloc] initWithStyle:UITableViewStyleInsetGrouped];
    details.title = [self nameForIdentity:app[@"id"]];
    details.rows = rows;
    [self.navigationController pushViewController:details animated:YES];
}
- (void)exportDiagnosticReport {
    if (self.presentedViewController)
        return; // Ignore repeated taps while the existing sheet is open.
    NSError *error = nil;
    NSData *data = IEBDiagnosticReport(self.model, self.processSnapshot, &error);
    NSString *text = IEBReadableDiagnosticReport(self.model, self.processSnapshot);
    IEBDiagnosticExport *export =
        data && !error ? [[IEBDiagnosticExport alloc] initWithJSON:data readableText:text error:&error] : nil;
    if (!export || error) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:IEBLocalized(@"REPORT_UNAVAILABLE", @"Report unavailable")
                             message:IEBLocalized(@"COULD_NOT_PREPARE_THE_DIAGNOSTIC_REPORT_TRY_AGAIN",
                                                  @"Could not prepare the diagnostic report. Try again.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:IEBLocalized(@"OK", @"OK")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:export.fileURLs
                                                                        applicationActivities:nil];
    __weak typeof(self) weakOwner = self;
    share.completionWithItemsHandler =
        ^(UIActivityType type, BOOL completed, NSArray *items, NSError *shareError) {
            (void)type;
            (void)completed;
            (void)items;
            NSError *cleanupError = nil;
            if (![export removeTemporaryFiles:&cleanupError])
                NSLog(@"IEB diagnostic temporary file cleanup failed after sharing.");
            if (shareError) {
                NSLog(@"IEB diagnostic sharing did not complete.");
                dispatch_async(dispatch_get_main_queue(), ^{
                    typeof(self) owner = weakOwner;
                    if (!owner.view.window || owner.presentedViewController)
                        return;
                    UIAlertController *alert = [UIAlertController
                        alertControllerWithTitle:IEBLocalized(@"SHARING_FAILED", @"Sharing failed")
                                         message:IEBLocalized(
                                                     @"EXPORT_THE_REPORT_AGAIN_AND_CHOOSE_A_DESTINATION",
                                                     @"Export the report again and choose a destination.")
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:IEBLocalized(@"OK", @"OK")
                                                              style:UIAlertActionStyleDefault
                                                            handler:nil]];
                    [owner presentViewController:alert animated:YES completion:nil];
                });
            }
        };
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}
@end
