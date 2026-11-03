#import "IEBCycleHistoryController.h"
#import "../Statistics/IEBCycleHistory.h"
#import "IEBStatisticsController.h"
#import <math.h>
static BOOL Number(id n) { return [n isKindOfClass:NSNumber.class] && isfinite([n doubleValue]); }
// Keep signs and colon-separated values in one LTR run inside Hebrew labels.
static NSString *NumericRun(NSString *text) { return [NSString stringWithFormat:@"\u2066%@\u2069", text]; }
static double DisplayedValue(id n, BOOL energy) {
    // Match the precision actually printed, preserving raw measurements in storage.
    return energy ? [[NSString stringWithFormat:@"%.1f", [n doubleValue]] doubleValue]
                  : round([n doubleValue]);
}
static NSString *Time(id n, BOOL delta) {
    if (!Number(n) || fabs([n doubleValue]) > 86400000 || (!delta && [n doubleValue] < 0))
        return @"—";
    double value = [n doubleValue];
    NSInteger seconds = (NSInteger)round(fabs(value));
    NSString *sign = delta && seconds ? (value > 0 ? @"+" : @"−") : @"";
    return NumericRun([NSString stringWithFormat:@"%@%02ld:%02ld:%02ld", sign, (long)(seconds / 3600),
                                                 (long)(seconds / 60 % 60), (long)(seconds % 60)]);
}
@interface IEBCycleComparisonController : UITableViewController
@property(nonatomic, copy) NSArray *metrics;
@property(nonatomic, copy) NSString *explanation;
- (instancetype)initWithFirst:(NSDictionary *)a second:(NSDictionary *)b;
@end
@implementation IEBCycleComparisonController
- (instancetype)initWithFirst:(NSDictionary *)a second:(NSDictionary *)b {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = IEBText(@"Cycle Comparison", @"השוואת מחזורים");
        NSDictionary *difference = IEBCompareCycleSummaries(a, b);
        NSMutableArray *metrics = [NSMutableArray new];
        NSArray *specs = @[
            @[ IEBText(@"Duration", @"משך המחזור"), @"duration", @"duration_delta" ],
            @[ IEBText(@"Screen On", @"מסך פעיל"), @"screen_on", @"screen_on_delta" ],
            @[ IEBText(@"Screen Off Usage", @"שימוש כשהמסך כבוי"), @"screen_off", @"screen_off_delta" ]
        ];
        for (NSUInteger i = 0; i < specs.count; i++) {
            NSArray *spec = specs[i];
            NSString *first = Time(a[spec[1]], NO);
            NSString *second = Time(b[spec[1]], NO);
            // The domain comparison decides availability. Presentation subtraction uses
            // the displayed precision so A, B and their difference agree to the last digit.
            id displayedDifference = Number(difference[spec[2]])
                                         ? @(DisplayedValue(a[spec[1]], NO) - DisplayedValue(b[spec[1]], NO))
                                         : NSNull.null;
            NSString *delta = Time(displayedDifference, YES);
            [metrics addObject:@[
                spec[0], [NSString stringWithFormat:IEBText(@"A: %@ · B: %@\nDifference (A − B): %@",
                                                            @"א: %@ · ב: %@\nהפרש (א פחות ב): %@"),
                                                    first, second, delta]
            ]];
        }
        id relative = difference[@"energy_rate_relative_percent"];
        NSString *rateText = IEBText(@"— · A relative rate cannot be calculated from the available data.",
                                     @"— · אין די נתונים לחישוב קצב יחסי.");
        BOOL shortCycle = (Number(a[@"duration"]) && [a[@"duration"] doubleValue] < 60) ||
                          (Number(b[@"duration"]) && [b[@"duration"] doubleValue] < 60);
        if (Number(relative)) {
            double percent = DisplayedValue(relative, YES);
            NSString *amount = NumericRun([NSString stringWithFormat:@"%.1f%%", fabs(percent)]);
            rateText = percent > 0
                           ? [NSString stringWithFormat:IEBText(@"A's estimated rate is %@ higher than B's.",
                                                                @"קצב הצריכה המשוער בא׳ גבוה ב־%@ מב׳."),
                                                        amount]
                       : percent < 0
                           ? [NSString stringWithFormat:IEBText(@"A's estimated rate is %@ lower than B's.",
                                                                @"קצב הצריכה המשוער בא׳ נמוך ב־%@ מב׳."),
                                                        amount]
                           : IEBText(@"A and B have similar estimated rates at the displayed precision.",
                                     @"קצב הצריכה המשוער בא׳ ובב׳ דומה ברמת הדיוק המוצגת.");
        } else if (shortCycle) {
            rateText = IEBText(@"— · A cycle is shorter than one minute; there is not enough data for a "
                               @"useful rate comparison.",
                               @"— · אחד המחזורים קצר מדקה; אין די נתונים להשוואת קצב שימושית.");
        } else if ([difference[@"comparable_energy"] boolValue] && [b[@"energy_per_hour"] doubleValue] == 0) {
            rateText = IEBText(@"— · B has no positive estimated rate to use as a comparison baseline.",
                               @"— · אין בב׳ קצב צריכה חיובי שיכול לשמש בסיס להשוואה.");
        }
        NSString *caution = IEBText(@"This is a relative estimate, not battery percentage lost.",
                                    @"זהו שינוי יחסי באומדן, ולא אחוזי סוללה שהמכשיר איבד.");
        if ([a[@"energy_allocation_estimated"] boolValue] || [b[@"energy_allocation_estimated"] boolValue])
            caution = [caution
                stringByAppendingString:
                    IEBText(@" Some energy records are allocated proportionally across cycle boundaries.",
                            @" חלק מרשומות הצריכה חולקו באופן יחסי בגבולות המחזור.")];
        [metrics addObject:@[
            IEBText(@"Relative consumption rate — estimate", @"קצב צריכה יחסי — אומדן"),
            [NSString stringWithFormat:@"%@\n%@", rateText, caution]
        ]];
        _metrics = [metrics copy];
        NSMutableArray *notes = [NSMutableArray
            arrayWithObject:
                IEBText(@"A is the first selected cycle; B is the second. Differences use the displayed "
                        @"precision. Unknown values are not zero.",
                        @"א הוא המחזור שנבחר ראשון; ב נבחר שני. ההפרשים מחושבים לפי הדיוק המוצג. "
                        @"נתונים חסרים אינם אפס.")];
        if ([a[@"duration"] doubleValue] != [b[@"duration"] doubleValue])
            [notes
                addObject:
                    IEBText(
                        @"Durations differ. Screen-time totals are not directly equivalent; estimated energy "
                        @"is normalized per hour.",
                        @"המחזורים באורכים שונים. זמני המסך המצטברים אינם שקולים; מדד הצריכה מנורמל לשעה.")];
        if (![a[@"power_complete"] boolValue] || ![b[@"power_complete"] boolValue] ||
            [a[@"activity_pending_seconds"] doubleValue] > 1 ||
            [b[@"activity_pending_seconds"] doubleValue] > 1)
            [notes
                addObject:
                    IEBText(@"At least one saved cycle contains gaps or delayed activity. Treat its totals "
                            @"as partial.",
                            @"לפחות אחד המחזורים כולל פערים או פעילות שממתינה לרישום. הסיכומים שלו חלקיים.")];
        if (![difference[@"comparable_energy"] boolValue])
            [notes
                addObject:IEBText(
                              @"Insufficient retained energy records for a supported consumption comparison.",
                              @"אין די רשומות צריכה שמורות להשוואת צריכה מבוססת.")];
        [notes addObject:
                   IEBText(
                       @"Relative consumption compares the estimated energy rate per hour in A with B. "
                       @"It does not measure battery percentage lost or establish complete per-app coverage.",
                       @"הקצב היחסי משווה את אומדן הצריכה לשעה בא׳ לב׳. הוא אינו מודד ירידה באחוזי "
                       @"הסוללה ואינו מבטיח כיסוי מלא של כל אפליקציה.")];
        _explanation = [notes componentsJoinedByString:@"\n\n"];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return self.metrics.count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    NSArray *row = self.metrics[(NSUInteger)path.row];
    cell.textLabel.text = row[0];
    cell.detailTextLabel.text = row[1];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return self.explanation;
}
@end
@interface IEBCycleHistoryController ()
@property(nonatomic, copy) NSArray * (^listLoader)(NSError **);
@property(nonatomic, copy) NSDictionary * (^detailLoader)(NSDictionary *, NSError **);
@property(nonatomic, copy) NSArray *records;
@property(nonatomic, strong) NSMutableArray<NSString *> *selectedIDs;
@property(nonatomic, strong) NSError *loadError;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) BOOL active, loading, comparing;
@property(nonatomic) NSUInteger generation;
@end
@implementation IEBCycleHistoryController
- (instancetype)initWithListLoader:(NSArray<NSDictionary *> * (^)(NSError **))listLoader
                      detailLoader:(NSDictionary * (^)(NSDictionary *, NSError **))detailLoader {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _listLoader = [listLoader copy];
        _detailLoader = [detailLoader copy];
        _selectedIDs = [NSMutableArray new];
        _queue = dispatch_queue_create("com.idonamaan.ieb.history", DISPATCH_QUEUE_SERIAL);
        self.title = IEBText(@"Saved Cycles", @"מחזורים שמורים");
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self
                            action:@selector(reloadHistory)
                  forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:IEBText(@"Clear", @"נקה בחירה")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(clearSelection)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.active = YES;
    [self reloadHistory];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.active = NO;
    self.generation++;
}
- (void)clearSelection {
    if (self.comparing)
        self.generation++;
    self.comparing = NO;
    [self.selectedIDs removeAllObjects];
    [self.tableView reloadData];
}
- (void)reloadHistory {
    self.loading = YES;
    self.comparing = NO;
    [self.selectedIDs removeAllObjects];
    NSUInteger generation = ++self.generation;
    NSArray * (^load)(NSError **) = [self.listLoader copy];
    __weak typeof(self) weak = self;
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSArray *records = load ? load(&error) : nil;
        if (!records && !error)
            error = [NSError errorWithDomain:@"IEBCycleHistory" code:1 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner = weak;
            if (!owner || !owner.active || owner.generation != generation)
                return;
            owner.loading = NO;
            owner.loadError = error;
            owner.records = records ?: @[];
            [owner.refreshControl endRefreshing];
            [owner.tableView reloadData];
        });
    });
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return MAX(1, (NSInteger)self.records.count);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return self.comparing ? IEBText(@"Preparing comparison…", @"מכין השוואה…")
                          : IEBText(@"Select two closed cycles", @"בחר שני מחזורים סגורים להשוואה");
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    (void)section;
    return IEBText(
        @"After installing this update, reload PerfPowerServices (for example, restart userspace with "
        @"your jailbreak tool) to enable history collection. Reopening Settings alone is insufficient. "
        @"Newest first · at most 20 cycles. Closed summaries are saved by the collector before old cycle "
        @"data is cleared. Activity may arrive late. Only selected cycles query retained energy data; "
        @"expired records remain unavailable.",
        @"לאחר התקנת העדכון יש לטעון מחדש את PerfPowerServices (למשל באמצעות הפעלה מחדש של "
        @"userspace בכלי הפריצה) כדי להפעיל שמירת היסטוריה. פתיחה מחדש של הגדרות בלבד אינה מספיקה. "
        @"החדש ביותר ראשון · עד 20 מחזורים. שירות האיסוף שומר סיכום מחזור סגור לפני ניקוי נתוניו הישנים. "
        @"פעילות עשויה להגיע באיחור. נתוני צריכה נשלפים רק למחזורים שנבחרו; רישומים שפגו נשארים לא זמינים.");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    if (!self.records.count) {
        cell.textLabel.text =
            self.loading     ? IEBText(@"Loading saved cycles…", @"טוען מחזורים שמורים…")
            : self.loadError ? IEBText(@"Could not read history. Pull to retry.",
                                       @"לא ניתן לקרוא היסטוריה. משוך לניסיון נוסף.")
                             : IEBText(@"No closed cycles saved yet.", @"עדיין אין מחזורים סגורים שמורים.");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *record = self.records[(NSUInteger)path.row];
    cell.textLabel.text =
        [NSString stringWithFormat:IEBText(@"Cycle %ld · duration %@", @"מחזור %ld · משך %@"),
                                   (long)path.row + 1, Time(record[@"duration"], NO)];
    cell.detailTextLabel.text =
        [NSString stringWithFormat:IEBText(@"Screen on %@ · screen off %@\nActivity pending %@%@",
                                           @"מסך פעיל %@ · שימוש כשהמסך כבוי %@\nממתין לרישום פעילות %@%@"),
                                   Time(record[@"screen_on"], NO), Time(record[@"screen_off"], NO),
                                   Time(record[@"activity_pending_seconds"], NO),
                                   [record[@"power_complete"] boolValue]
                                       ? @""
                                       : IEBText(@" · incomplete cycle", @" · מחזור חלקי")];
    cell.accessoryType = [self.selectedIDs containsObject:record[@"id"]] ? UITableViewCellAccessoryCheckmark
                                                                         : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (self.loading || self.comparing || path.row < 0 || path.row >= (NSInteger)self.records.count)
        return;
    NSDictionary *record = self.records[(NSUInteger)path.row];
    NSString *identity = record[@"id"];
    if ([self.selectedIDs containsObject:identity])
        [self.selectedIDs removeObject:identity];
    else {
        if (self.selectedIDs.count >= 2)
            [self.selectedIDs removeAllObjects];
        [self.selectedIDs addObject:identity];
    }
    [self.tableView reloadData];
    if (self.selectedIDs.count != 2)
        return;
    NSMutableArray *chosen = [NSMutableArray new];
    for (NSString *key in self.selectedIDs)
        for (NSDictionary *item in self.records)
            if ([item[@"id"] isEqual:key])
                [chosen addObject:item];
    if (chosen.count != 2)
        return;
    self.comparing = YES;
    NSUInteger generation = ++self.generation;
    NSDictionary * (^load)(NSDictionary *, NSError **) = [self.detailLoader copy];
    __weak typeof(self) weak = self;
    [self.tableView reloadData];
    dispatch_async(self.queue, ^{
        NSMutableArray *enriched = [NSMutableArray new];
        for (NSDictionary *item in chosen) {
            NSError *error = nil;
            NSDictionary *loaded = load ? load(item, &error) : nil;
            if (!loaded || error) {
                NSMutableDictionary *fallback = [item mutableCopy];
                fallback[@"energy_total"] = NSNull.null;
                fallback[@"energy_per_hour"] = NSNull.null;
                fallback[@"energy_partial"] = @YES;
                loaded = fallback;
            }
            [enriched addObject:loaded];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner = weak;
            if (!owner || !owner.active || owner.generation != generation)
                return;
            owner.comparing = NO;
            [owner.tableView reloadData];
            IEBCycleComparisonController *comparison =
                [[IEBCycleComparisonController alloc] initWithFirst:enriched[0] second:enriched[1]];
            [owner.navigationController pushViewController:comparison animated:YES];
        });
    });
}
@end
