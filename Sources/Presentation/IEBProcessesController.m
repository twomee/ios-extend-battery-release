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
                             ? IEBText(@"Root reader", @"קריאה בהרשאות root")
                             : IEBText(@"Limited permissions", @"הרשאות מוגבלות");
    NSString *state = [status[@"state"] isEqual:@"available"]
                          ? IEBText(@"Snapshot available", @"תמונת התהליכים זמינה")
                      : [status[@"state"] isEqual:@"partial"]
                          ? IEBText(@"Partial snapshot · energy matching may be unavailable",
                                    @"תמונת תהליכים חלקית · ייתכן שלא יוצגו אחוזי סוללה")
                          : IEBText(@"Snapshot unavailable", @"תמונת התהליכים אינה זמינה");
    NSString *reason = @"";
    if (![status[@"provider"] isEqual:@"root"]) {
        if ([status[@"reason"] isEqual:@"caller-denied"])
            reason = IEBText(@"Caller authentication denied.", @"אימות הרשאת הקורא נדחה.");
        else if ([status[@"reason"] isEqual:@"service-timeout"])
            reason = IEBText(@"Root service response timed out.", @"שירות root לא השיב בזמן.");
        else
            reason = IEBText(@"Root service unavailable or response invalid.",
                             @"שירות root אינו זמין או שתשובתו אינה תקינה.");
    }
    return [NSString
        stringWithFormat:IEBText(@"%@ · %@\nReadable %@ · denied %@ · vanished %@ · unnamed %@%@\n%@",
                                 @"%@ · %@\nזמינים %@ · ללא הרשאה %@ · נעלמו %@ · ללא שם %@%@\n%@"),
                         provider, state, CountText(status[@"readable"]), CountText(status[@"denied"]),
                         CountText(status[@"vanished"]), CountText(status[@"unnamed"]),
                         [status[@"truncated"] boolValue] ? IEBText(@" · truncated", @" · הרשימה נקטעה")
                                                          : @"",
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
        self.title = IEBText(@"Live Processes", @"תהליכים פעילים");
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
    self.searchController.searchBar.placeholder = IEBText(@"Process name or PID", @"שם תהליך או PID");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.sortControl = [[UISegmentedControl alloc] initWithItems:@[
        @"CPU", IEBText(@"CPU time", @"זמן CPU"), IEBText(@"Battery", @"סוללה"), IEBText(@"Name", @"שם")
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
               ? [NSString stringWithFormat:IEBText(@"Showing %lu of %lu\n%@", @"מוצגים %lu מתוך %lu\n%@"),
                                            (unsigned long)self.rows.count, (unsigned long)self.allRows.count,
                                            IEBProcessStatusText(self.snapshot)]
               : IEBText(@"Reading process permissions…", @"בודק הרשאות תהליכים…");
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    (void)section;
    NSString *provider = [self.snapshot[@"reader_provider"] isEqual:@"root-service"]
                             ? IEBText(@"Read through the root service. Kernel task (PID 0) is excluded.",
                                       @"הנתונים נקראים באמצעות שירות root. משימת הקרנל (PID 0) אינה נכללת.")
                             : IEBText(@"Root service unavailable; limited process access.",
                                       @"שירות root אינו זמין; הגישה לתהליכים מוגבלת.");
    return [[provider stringByAppendingString:@"\n"]
        stringByAppendingString:
            [NSString
                stringWithFormat:
                    IEBText(
                        @"%lu readable · %lu permission denied. CPU time is cumulative for the current "
                        @"process "
                        @"lifetime; CPU %% is sampled every 5 seconds and can exceed 100 across cores. "
                        @"Battery "
                        @"%% is the matched source's share in the full unplug cycle, including prior "
                        @"instances. "
                        @"It is not calculated from CPU. Unmatched/ambiguous sources remain unavailable.",
                        @"%lu תהליכים זמינים · %lu ללא הרשאת קריאה. זמן CPU מצטבר מאז תחילת מופע התהליך; "
                        @"אחוז "
                        @"CPU נמדד כל 5 שניות ויכול לעבור 100 במספר ליבות. אחוז הסוללה הוא חלק מקור האנרגיה "
                        @"במחזור הניתוק המלא, כולל מופעים קודמים. הוא אינו מחושב מה־CPU. שיוך חסר או לא "
                        @"חד־משמעי "
                        @"נשאר לא זמין."),
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
                ? IEBText(@"No processes match the search.", @"לא נמצאו תהליכים שתואמים לחיפוש.")
            : self.snapshot ? IEBText(@"Process CPU information is unavailable with current permissions.",
                                      @"נתוני CPU לתהליכים אינם זמינים בהרשאות הנוכחיות.")
                            : IEBText(@"Loading…", @"טוען…");
        return cell;
    }
    IEBSourceCell *cell = [table dequeueReusableCellWithIdentifier:@"process"];
    if (!cell)
        cell = [[IEBSourceCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"process"];
    NSDictionary *row = self.rows[(NSUInteger)path.row];
    id percent = row[@"energy_percent"], cpu = row[@"cpu_percent"];
    NSString *details =
        [NSString stringWithFormat:IEBText(@"PID %@\nCPU lifetime: %@\nCurrent CPU: %@\n%@",
                                           @"PID %@\nזמן CPU מצטבר: %@\nCPU נוכחי: %@\n%@"),
                                   row[@"pid"], CPUTime(row[@"cpu_seconds"]),
                                   [cpu isKindOfClass:NSNumber.class]
                                       ? [NSString stringWithFormat:@"%.1f%%", [cpu doubleValue]]
                                       : IEBText(@"Waiting for second sample", @"ממתין לדגימה נוספת"),
                                   [percent isKindOfClass:NSNumber.class]
                                       ? IEBText(@"Battery share · full unplug cycle",
                                                 @"חלק בצריכת הסוללה · מחזור הניתוק המלא")
                                       : IEBText(@"No unambiguous energy attribution",
                                                 @"אין שיוך חד־משמעי לצריכת סוללה")];
    [cell configureName:[row[@"name"] length] ? row[@"name"] : IEBText(@"Unnamed process", @"תהליך ללא שם")
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
