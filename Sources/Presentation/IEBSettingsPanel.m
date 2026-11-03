#import "IEBSettingsPanel.h"
#import "IEBNativeBatteryCells.h"
#import "IEBNativeChartController.h"
#import <objc/message.h>
#import <objc/runtime.h>

// Preserve native rows through the graph and screen-time summary; append cycle source categories.
@interface IEBPrefixDataSource : NSObject <UITableViewDataSource>
@property(nonatomic, weak) id<UITableViewDataSource> target;
@property(nonatomic, strong) NSIndexPath *last, *range, *graphPath, *timePath;
@property(nonatomic, weak) IEBStatisticsController *statistics;
@property(nonatomic, strong) NSHashTable<UITableViewCell *> *graphCells, *timeCells;
- (void)refreshNativeCells;
- (void)restoreNativeCells;
@end
@implementation IEBPrefixDataSource
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.target respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return self.target;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    NSInteger count =
        [self.target respondsToSelector:_cmd] ? [self.target numberOfSectionsInTableView:table] : 1;
    return MIN(count, self.last.section + 1);
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    NSInteger count = [self.target tableView:table numberOfRowsInSection:section];
    return section == self.last.section ? MIN(count, self.last.row + 1) : count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [self.target tableView:table cellForRowAtIndexPath:path];
    if ([path isEqual:self.graphPath]) {
        if (IEBAttachNativeChart(cell, self.statistics.nativeChartView))
            [self.graphCells addObject:cell];
    } else if ([path isEqual:self.timePath]) {
        [self.statistics updateNativeTimeUsageCell:cell];
        [self.timeCells addObject:cell];
    }
    return cell;
}
- (void)refreshNativeCells {
    for (UITableViewCell *cell in self.timeCells)
        [self.statistics updateNativeTimeUsageCell:cell];
    for (UITableViewCell *cell in self.graphCells)
        IEBLayoutNativeChart(cell);
}
- (void)restoreNativeCells {
    IEBRestoreNativeChartView(self.statistics.nativeChartView);
    for (UITableViewCell *cell in self.graphCells)
        IEBRestoreNativeChart(cell);
    for (UITableViewCell *cell in self.timeCells)
        IEBRestoreNativeTimeUsage(cell);
    [self.graphCells removeAllObjects];
    [self.timeCells removeAllObjects];
}
@end

@interface IEBPanel : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, strong) IEBStatisticsController *controller;
@property(nonatomic, weak) UITableView *table;
@property(nonatomic, strong) IEBPrefixDataSource *prefix;
@property(nonatomic, strong) UIView *originalFooter;
@property(nonatomic) BOOL observing, layingOut, scheduled;
@end
@implementation IEBPanel
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    (void)keyPath;
    (void)object;
    (void)change;
    if (context != (__bridge void *)self) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (self.scheduled)
        return;
    self.scheduled = YES;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weak.scheduled = NO;
        if (weak.owner)
            IEBLayoutSettingsPanel(weak.owner);
    });
}
- (void)dealloc {
    if (_observing)
        [_controller.tableView removeObserver:self forKeyPath:@"contentSize" context:(__bridge void *)self];
}
@end
static void BindNativePresentation(IEBStatisticsController *statistics, UITableView *native) {
    statistics.nativeChartPresentation = IEBNativeChartPresentationForTable(native);
    __weak UITableView *weakNative = native;
    statistics.nativeChartPresentationProvider = ^NSDictionary * {
        return IEBNativeChartPresentationForTable(weakNative);
    };
}
static const void *PanelKey = &PanelKey;
static const void *RangeKey = &RangeKey;
void IEBRememberSettingsRange(UIViewController *owner, NSInteger range) {
    if (range >= 0 && range <= 2)
        objc_setAssociatedObject(owner, RangeKey, @(range), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void IEBSyncSettingsRange(UIViewController *owner, UISegmentedControl *control) {
    NSNumber *range = objc_getAssociatedObject(owner, RangeKey);
    if (range && control && control.numberOfSegments > (NSUInteger)range.integerValue)
        [UIView performWithoutAnimation:^{
            control.selectedSegmentIndex = range.integerValue;
        }];
}
static void FindNativeRows(UITableView *table, IEBPrefixDataSource *prefix, NSIndexPath *range);
void IEBLayoutSettingsPanel(UIViewController *owner) {
    IEBPanel *panel = objc_getAssociatedObject(owner, PanelKey);
    if (!panel || panel.layingOut || !panel.table)
        return;
    panel.layingOut = YES;
    UITableView *native = panel.table;
    if (native.dataSource != panel.prefix) {
        [panel.prefix restoreNativeCells];
        panel.prefix.target = native.dataSource;
        FindNativeRows(native, panel.prefix, panel.prefix.range);
        panel.controller.nativeTablePresentation = panel.prefix.timePath != nil;
        native.dataSource = panel.prefix;
        [native reloadData];
        [panel.controller.tableView reloadData];
    }
    UITableView *stats = panel.controller.tableView;
    CGFloat width = native.bounds.size.width;
    CGSize oldSize = stats.frame.size;
    for (int i = 0; i < 3; i++) {
        CGFloat height = MAX(1, stats.contentSize.height);
        CGRect frame = stats.frame;
        frame.size = CGSizeMake(width, height);
        stats.frame = frame;
        [stats layoutIfNeeded];
    }
    if (native.tableFooterView != stats || fabs(oldSize.height - stats.contentSize.height) > 0.5 ||
        fabs(oldSize.width - width) > 0.5) {
        CGRect frame = stats.frame;
        frame.size = CGSizeMake(width, MAX(1, stats.contentSize.height));
        stats.frame = frame;
        native.tableFooterView = stats;
    }
    stats.contentOffset = CGPointZero;
    panel.layingOut = NO;
}
void IEBDismissSettingsPanel(UIViewController *owner) {
    IEBPanel *panel = objc_getAssociatedObject(owner, PanelKey);
    if (!panel)
        return;
    objc_setAssociatedObject(owner, PanelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITableView *native = panel.table;
    panel.controller.nativePresentationDidUpdate = nil;
    [panel.prefix restoreNativeCells];
    [panel.controller endNativeTablePresentation];
    [panel.controller willMoveToParentViewController:nil];
    [panel.controller beginAppearanceTransition:NO animated:NO];
    if (native.tableFooterView == panel.controller.view)
        native.tableFooterView = panel.originalFooter;
    [panel.controller.view removeFromSuperview];
    [panel.controller removeFromParentViewController];
    [panel.controller endAppearanceTransition];
    if (native.dataSource == panel.prefix)
        native.dataSource = panel.prefix.target;
    [native reloadData];
}
static UITableView *NativeTable(UISegmentedControl *segment, NSIndexPath **path) {
    UIView *cell = segment.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class])
        cell = cell.superview;
    UIView *ancestor = cell.superview;
    while (ancestor && ![ancestor isKindOfClass:UITableView.class])
        ancestor = ancestor.superview;
    UITableView *table = (UITableView *)ancestor;
    if (path)
        *path = cell ? [table indexPathForCell:(UITableViewCell *)cell] : nil;
    return table;
}
static void FindNativeRows(UITableView *table, IEBPrefixDataSource *prefix, NSIndexPath *range) {
    prefix.range = range;
    prefix.last = range;
    prefix.graphPath = prefix.timePath = nil;
    if (!IEBNativeTimeUsageSupported() || ![IEBNativeChartController isSupported])
        return;
    id<UITableViewDataSource> source = prefix.target;
    NSInteger sections = [source respondsToSelector:@selector(numberOfSectionsInTableView:)]
                             ? [source numberOfSectionsInTableView:table]
                             : 1;
    NSUInteger inspected = 0;
    NSIndexPath *graph = nil;
    for (NSInteger section = range.section; section < sections && inspected < 32; section++) {
        NSInteger rows = [source tableView:table numberOfRowsInSection:section];
        for (NSInteger row = section == range.section ? range.row + 1 : 0; row < rows && inspected < 32;
             row++) {
            inspected++;
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            // A native cell factory can move the shared graph view out of its visible cell.
            // Discover row kinds from specifier metadata without constructing any views.
            Class cellClass = IEBNativeCellClassAtPath(source, path);
            if ([cellClass isSubclassOfClass:NSClassFromString(@"PLBatteryUIGraphViewTableCell")])
                graph = path;
            if (graph && [cellClass isSubclassOfClass:NSClassFromString(@"PLBatteryUITimeUsageCell")]) {
                prefix.graphPath = graph;
                prefix.timePath = prefix.last = path;
                return;
            }
        }
    }
}
BOOL IEBShowSettingsPanel(UIViewController *owner, UISegmentedControl *segment,
                          IEBStatisticsController *statistics, void (^selectRange)(NSInteger)) {
    (void)selectRange; // The original, live range control remains in the native table.
    if (objc_getAssociatedObject(owner, PanelKey))
        return YES;
    if (!segment || segment.numberOfSegments != 3)
        return NO;
    NSIndexPath *path = nil;
    UITableView *native = NativeTable(segment, &path);
    if (!native || !path || !native.dataSource)
        return NO;
    BindNativePresentation(statistics, native);
    IEBPanel *panel = [IEBPanel new];
    panel.owner = owner;
    panel.table = native;
    panel.controller = statistics;
    panel.originalFooter = native.tableFooterView;
    panel.prefix = [IEBPrefixDataSource new];
    panel.prefix.target = native.dataSource;
    panel.prefix.statistics = statistics;
    panel.prefix.graphCells = [NSHashTable weakObjectsHashTable];
    panel.prefix.timeCells = [NSHashTable weakObjectsHashTable];
    FindNativeRows(native, panel.prefix, path);
    statistics.nativeTablePresentation = panel.prefix.timePath != nil;
    __weak IEBPrefixDataSource *weakPrefix = panel.prefix;
    statistics.nativePresentationDidUpdate = ^{
        [weakPrefix refreshNativeCells];
    };
    objc_setAssociatedObject(owner, PanelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [owner addChildViewController:statistics];
    [statistics beginAppearanceTransition:YES animated:NO];
    [statistics beginNativeTablePresentationInOwner:owner];
    statistics.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    statistics.tableView.scrollEnabled = NO;
    statistics.tableView.contentInset = UIEdgeInsetsZero;
    statistics.refreshControl = nil;
    [statistics.tableView addObserver:panel
                           forKeyPath:@"contentSize"
                              options:0
                              context:(__bridge void *)panel];
    panel.observing = YES;
    panel.layingOut = YES;
    native.dataSource = panel.prefix;
    [native reloadData];
    panel.layingOut = NO;
    IEBLayoutSettingsPanel(owner);
    [statistics didMoveToParentViewController:owner];
    [statistics endAppearanceTransition];
    return YES;
}
BOOL IEBHasSettingsPanel(UIViewController *owner) { return objc_getAssociatedObject(owner, PanelKey) != nil; }
void IEBRebindSettingsPanel(UIViewController *owner, UISegmentedControl *segment) {
    IEBPanel *panel = objc_getAssociatedObject(owner, PanelKey);
    if (!panel || panel.layingOut)
        return;
    NSIndexPath *path = nil;
    UITableView *table = NativeTable(segment, &path);
    if (path && table.dataSource && (table != panel.table || ![path isEqual:panel.prefix.range])) {
        panel.layingOut = YES;
        [panel.prefix restoreNativeCells];
        if (table != panel.table) {
            UITableView *old = panel.table;
            if (old.tableFooterView == panel.controller.view)
                old.tableFooterView = panel.originalFooter;
            if (old.dataSource == panel.prefix)
                old.dataSource = panel.prefix.target;
            [old reloadData];
            panel.table = table;
            BindNativePresentation(panel.controller, table);
            panel.originalFooter = table.tableFooterView;
            panel.prefix.target = table.dataSource;
            table.dataSource = panel.prefix;
        }
        FindNativeRows(table, panel.prefix, path);
        panel.controller.nativeTablePresentation = panel.prefix.timePath != nil;
        [table reloadData];
        panel.layingOut = NO;
    }
    IEBLayoutSettingsPanel(owner);
}

BOOL IEBSelectNativeRange(UIViewController *owner, UISegmentedControl *control, id specifier, BOOL reversed,
                          NSInteger range) {
    if (!owner || range < 0 || range > 1)
        return NO;
    IEBRememberSettingsRange(owner, range);
    IEBSyncSettingsRange(owner, control);
    SEL setter = sel_registerName("setBatteryUIQueryRange:specifier:");
    Method method = class_getInstanceMethod(owner.class, setter);
    if (specifier && method && strcmp(method_getTypeEncoding(method), "v32@0:8@16@24") == 0) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(owner, setter, reversed ? specifier : @(range),
                                                  reversed ? @(range) : specifier);
        return YES;
    }
    if (control && control.numberOfSegments > (NSUInteger)range) {
        control.selectedSegmentIndex = range;
        [control sendActionsForControlEvents:UIControlEventValueChanged];
        return YES;
    }
    // A native table rebuild can remove both the old specifier and its cell.
    // Restore the original view so the user can select a live native range there.
    IEBDismissSettingsPanel(owner);
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                    IEBLocalized(@"NATIVE_BATTERY_VIEW_RESTORED_SELECT_THE_RANGE_AGAIN",
                                                 @"Native battery view restored. Select the range again."));
    return NO;
}
