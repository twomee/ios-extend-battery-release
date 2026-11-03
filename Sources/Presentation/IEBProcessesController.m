#import "IEBProcessesController.h"
#import "../Diagnostics/IEBProcessAttribution.h"
#import "../Diagnostics/IEBProcessQuery.h"
#import "../Diagnostics/IEBProcessReaderStatus.h"
#import "IEBSourceCell.h"
#import "IEBStatisticsController.h"
static NSString *CPUTime(id n) {
    return [n isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%.2f s", [n doubleValue]] : @"—";
}
static NSString *CountText(id value) { return value == NSNull.null ? @"—" : [value description]; }
NSString *IEBProcessStatusText(NSDictionary *snapshot) {
    NSDictionary *status = IEBProcessReaderStatus(snapshot);
    NSString *provider = [status[@"provider"] isEqual:@"root"]
                             ? IEBLocalized(@"ROOT_READER", @"Root reader")
                             : IEBLocalized(@"LIMITED_PERMISSIONS", @"Limited permissions");
    NSString *state = [status[@"state"] isEqual:@"available"]
                          ? IEBLocalized(@"SNAPSHOT_AVAILABLE", @"Snapshot available")
                      : [status[@"state"] isEqual:@"partial"]
                          ? IEBLocalized(@"PARTIAL_SNAPSHOT_ENERGY_MATCHING_MAY_BE_UNAVAILABLE",
                                         @"Partial snapshot · energy matching may be unavailable")
                          : IEBLocalized(@"SNAPSHOT_UNAVAILABLE", @"Snapshot unavailable");
    NSString *reason = @"";
    if (![status[@"provider"] isEqual:@"root"]) {
        if ([status[@"reason"] isEqual:@"caller-denied"])
            reason = IEBLocalized(@"CALLER_AUTHENTICATION_DENIED", @"Caller authentication denied.");
        else if ([status[@"reason"] isEqual:@"service-timeout"])
            reason = IEBLocalized(@"ROOT_SERVICE_RESPONSE_TIMED_OUT", @"Root service response timed out.");
        else
            reason = IEBLocalized(@"ROOT_SERVICE_UNAVAILABLE_OR_RESPONSE_INVALID",
                                  @"Root service unavailable or response invalid.");
    }
    return [NSString
        stringWithFormat:IEBLocalized(@"READABLE_DENIED_VANISHED_UNNAMED",
                                      @"%@ · %@\nReadable %@ · denied %@ · vanished %@ · unnamed %@%@\n%@"),
                         provider, state, CountText(status[@"readable"]), CountText(status[@"denied"]),
                         CountText(status[@"vanished"]), CountText(status[@"unnamed"]),
                         [status[@"truncated"] boolValue] ? IEBLocalized(@"TRUNCATED", @" · truncated") : @"",
                         reason];
}
@interface IEBProcessesController ()
@property(nonatomic, copy) NSDictionary * (^loader)(void);
@property(nonatomic, strong) NSDictionary *snapshot, *catalog;
@property(nonatomic, copy) NSArray *rows;
@property(nonatomic, copy) NSArray *allRows;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) UISegmentedControl *sortControl;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL active, loading;
@property(nonatomic) NSUInteger generation;
@end
@implementation IEBProcessesController
- (instancetype)initWithLoader:(NSDictionary * (^)(void))loader {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _loader = [loader copy];
        self.title = IEBLocalized(@"LIVE_PROCESSES", @"Live Processes");
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder =
        IEBLocalized(@"PROCESS_NAME_OR_PID", @"Process name or PID");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.sortControl = [[UISegmentedControl alloc] initWithItems:@[
        @"CPU", IEBLocalized(@"CPU_TIME", @"CPU time"), IEBLocalized(@"BATTERY", @"Battery"),
        IEBLocalized(@"NAME", @"Name")
    ]];
    self.sortControl.selectedSegmentIndex = 0;
    [self.sortControl addTarget:self
                         action:@selector(applyQuery)
               forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 52)];
    self.sortControl.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.sortControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.sortControl.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.sortControl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.sortControl.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [self.sortControl.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    self.tableView.tableHeaderView = header;
}
- (void)applyQuery {
    NSArray *modes = @[ @"cpu", @"lifetime", @"energy", @"name" ];
    NSInteger index = self.sortControl.selectedSegmentIndex;
    self.rows =
        IEBQueryProcesses(self.allRows ?: @[], self.searchController.searchBar.text,
                          index >= 0 && index < (NSInteger)modes.count ? modes[(NSUInteger)index] : @"cpu");
    [self.tableView reloadData];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyQuery];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.active = YES;
    self.snapshot = nil;
    self.allRows = @[];
    [self applyQuery];
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
    if (!self.active || self.loading)
        return;
    self.loading = YES;
    NSUInteger generation = ++self.generation;
    NSDictionary * (^loader)(void) = [self.loader copy];
    NSDictionary *previous = self.snapshot;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *loaded = loader();
        NSDictionary *snapshot = loaded[@"snapshot"] ?: @{@"rows" : @[], @"status" : @"unavailable"};
        NSDictionary *joined =
            IEBProcessAttribution(loaded[@"sources"] ?: @[], loaded[@"catalog"] ?: @{}, snapshot, previous);
        NSArray *rows = joined[@"processes"];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strong = weak;
            if (!strong)
                return;
            strong.loading = NO;
            if (!strong.active)
                return;
            if (generation != strong.generation) {
                [strong refresh];
                return;
            }
            strong.snapshot = snapshot;
            strong.allRows = rows;
            strong.catalog = loaded[@"catalog"];
            [strong applyQuery];
        });
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return MAX(1, (NSInteger)self.rows.count);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return self.snapshot
               ? [NSString stringWithFormat:IEBLocalized(@"SHOWING_LU_OF_LU", @"Showing %lu of %lu\n%@"),
                                            (unsigned long)self.rows.count, (unsigned long)self.allRows.count,
                                            IEBProcessStatusText(self.snapshot)]
               : IEBLocalized(@"READING_PROCESS_PERMISSIONS", @"Reading process permissions…");
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    (void)section;
    NSString *provider =
        [self.snapshot[@"reader_provider"] isEqual:@"root-service"]
            ? IEBLocalized(@"READ_THROUGH_THE_ROOT_SERVICE_KERNEL_TASK_PID_0_IS_EXCLUDED",
                           @"Read through the root service. Kernel task (PID 0) is excluded.")
            : IEBLocalized(@"ROOT_SERVICE_UNAVAILABLE_LIMITED_PROCESS_ACCESS",
                           @"Root service unavailable; limited process access.");
    return [[provider stringByAppendingString:@"\n"]
        stringByAppendingString:
            [NSString stringWithFormat:
                          IEBLocalized(
                              @"LU_READABLE_LU_PERMISSION_DENIED_CPU_TIME_IS_CUMULATIVE_FOR_THE_CURRENT_PRO",
                              @"%lu readable · %lu permission denied. CPU time is cumulative for the current "
                              @"process lifetime; CPU %% is sampled every 5 seconds and can exceed 100 "
                              @"across cores. Battery %% is the matched source's share in the full unplug "
                              @"cycle, including prior instances. It is not calculated from CPU. "
                              @"Unmatched/ambiguous sources remain unavailable."),
                          (unsigned long)self.allRows.count,
                          [self.snapshot[@"permission_denied_count"] unsignedLongValue]]];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (!self.rows.count) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                       reuseIdentifier:nil];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.text =
            self.allRows.count
                ? IEBLocalized(@"NO_PROCESSES_MATCH_THE_SEARCH", @"No processes match the search.")
            : self.snapshot
                ? IEBLocalized(@"PROCESS_CPU_INFORMATION_IS_UNAVAILABLE_WITH_CURRENT_PERMISSIONS",
                               @"Process CPU information is unavailable with current permissions.")
                : IEBLocalized(@"LOADING", @"Loading…");
        return cell;
    }
    IEBSourceCell *cell = [table dequeueReusableCellWithIdentifier:@"process"];
    if (!cell)
        cell = [[IEBSourceCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"process"];
    NSDictionary *row = self.rows[(NSUInteger)path.row];
    id percent = row[@"energy_percent"], cpu = row[@"cpu_percent"];
    NSString *details = [NSString
        stringWithFormat:IEBLocalized(@"PID_CPU_LIFETIME_CURRENT_CPU",
                                      @"PID %@\nCPU lifetime: %@\nCurrent CPU: %@\n%@"),
                         row[@"pid"], CPUTime(row[@"cpu_seconds"]),
                         [cpu isKindOfClass:NSNumber.class]
                             ? [NSString stringWithFormat:@"%.1f%%", [cpu doubleValue]]
                             : IEBLocalized(@"WAITING_FOR_SECOND_SAMPLE", @"Waiting for second sample"),
                         [percent isKindOfClass:NSNumber.class]
                             ? IEBLocalized(@"BATTERY_SHARE_FULL_UNPLUG_CYCLE",
                                            @"Battery share · full unplug cycle")
                             : IEBLocalized(@"NO_UNAMBIGUOUS_ENERGY_ATTRIBUTION",
                                            @"No unambiguous energy attribution")];
    [cell configureName:[row[@"name"] length] ? row[@"name"]
                                              : IEBLocalized(@"UNNAMED_PROCESS", @"Unnamed process")
             percentage:[percent isKindOfClass:NSNumber.class]
                            ? [NSString stringWithFormat:@"%.1f%%", [percent doubleValue]]
                            : nil
                details:details
                   icon:self.catalog[row[@"energy_source"] ?: @""][@"icon"]];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
@end
