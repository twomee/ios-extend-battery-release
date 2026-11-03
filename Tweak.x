#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "IEBCommon.h"

// ===========================================================================
// iOSExtendBattery — adds a "Since Last Charge" tab to Settings > Battery.
//
// How it works (verified against the 21B91 / iPhone16,1 dumps):
//  * The battery pane is BatteryUsageUI.bundle loaded into Settings
//    (com.apple.Preferences). BatteryUIController (PSListController) builds
//    the specifier list; the "Last 24 Hours | Last 10 Days" control is a
//    PLBatteryUISegmentCell driven by a PSSpecifier whose action is
//    setBatteryUIQueryRange:specifier: with values {0,1}.
//  * All stats are fetched through PLBatteryUIBackendModel:
//      -addQueryType:(long)withEndDate:(NSDate*)withRange:(double)sec
//      withBucketSize:(double)sec   →  -runQuery  → powerlogd over XPC,
//    and the result is fed to -setUpBatteryUIDictionary: which drives every
//    Apple cell (chart, app breakdown, screen-on/off, Last Charge, …).
//  * Therefore the tweak simply adds a third segment; when selected it
//    re-runs the exact same query pipeline with the window remapped to
//    [last charge … now] inside -addQueryType. Everything else — chart,
//    per-app percentages, tap breakdowns, usage times — is rendered by
//    Apple's own code for that window.
// ===========================================================================

static BOOL iebSLCSelected = NO;      // user is on the "Since Last Charge" tab
static BOOL iebSLCQueryActive = NO;   // currently building a payload with the SLC window
static NSDate *iebSLCWindowStart = nil;
static double iebSLCSpanSeconds = 0.0;
static double iebSLCBucketSeconds = 3600.0;
static int iebSLCBaseRange = 0;       // 0 = render day-style, 1 = render week-style

static BOOL iebDebugEnabled = NO;
#define IEBLogRaw(fmt, ...) do { \
    NSLog(@"[IEB] " fmt, ##__VA_ARGS__); \
    NSString *_line = [NSString stringWithFormat:(@"[IEB] " fmt @"\n"), ##__VA_ARGS__]; \
    FILE *_f = fopen("/var/mobile/Library/Logs/ieb.log", "a"); \
    if (_f) { fputs(_line.UTF8String, _f); fclose(_f); } \
} while (0)
#define IEBLog(fmt, ...) IEBLogRaw(fmt, ##__VA_ARGS__)

#pragma mark - Ivar helpers

static int iebGetIntIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) {
        IEBLog(@"int ivar %s not found", name);
        return 0;
    }
    return *(int *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

static void iebSetIntIvar(id obj, const char *name, int value) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) {
        IEBLog(@"int ivar %s not found", name);
        return;
    }
    *(int *)((char *)(__bridge void *)obj + ivar_getOffset(iv)) = value;
}

static void iebSetObjectIvar(id obj, const char *name, id value) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) {
        IEBLog(@"object ivar %s not found", name);
        return;
    }
    object_setIvar(obj, iv, value);
}

#pragma mark - Localization

static NSDictionary *iebStringsTable(void) {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"en"      : @"Since Last Charge",
            @"he"      : @"מאז הטעינה האחרונה",
            @"ar"      : @"منذ آخر شحن",
            @"ru"      : @"С последней зарядки",
            @"uk"      : @"З останньої зарядки",
            @"es"      : @"Desde la última carga",
            @"es-419"  : @"Desde la última carga",
            @"fr"      : @"Depuis la dernière charge",
            @"de"      : @"Seit dem letzten Laden",
            @"it"      : @"Dall'ultima ricarica",
            @"pt-br"   : @"Desde a última carga",
            @"pt-pt"   : @"Desde a última carga",
            @"nl"      : @"Sinds laatste lading",
            @"sv"      : @"Sedan senaste laddning",
            @"pl"      : @"Od ostatniego ładowania",
            @"tr"      : @"Son şarjdan beri",
            @"zh-hans" : @"自上次充电",
            @"zh-hant" : @"自上次充電",
            @"ja"      : @"前回の充電以降",
            @"ko"      : @"마지막 충전 이후",
            @"hi"      : @"पिछली चार्ज के बाद से",
            @"id"      : @"Sejak pengisian terakhir",
            @"vi"      : @"Kể từ lần sạc cuối",
            @"th"      : @"ตั้งแต่ชาร์จครั้งล่าสุด",
        };
    });
    return table;
}

// Short title for the third segment control.
static NSString *iebSegmentTitle(void) {
    NSString *lang = [[NSLocale preferredLanguages] firstObject];
    NSDictionary *table = iebStringsTable();
    if (lang) {
        NSString *lower = [lang lowercaseString];
        NSString *hit = table[lower];
        if (!hit) {
            for (NSString *key in table) {
                if ([lower hasPrefix:key]) { hit = table[key]; break; }
            }
        }
        if (!hit) {
            // e.g. "de-DE" → "de"
            NSString *base = [lower componentsSeparatedByString:@"-"].firstObject;
            hit = table[base];
        }
        if (hit) return hit;
    }
    return @"Since Last Charge";
}

// Section-header text. Apple ships a ready-made localized string for this
// concept ("Time since last full charge") in BatteryUI.loctable — reuse it.
static NSString *iebHeaderTitle(void) {
    Class paneClass = NSClassFromString(@"BatteryUIController");
    if (paneClass) {
        NSBundle *paneBundle = [NSBundle bundleForClass:paneClass];
        NSString *s = [paneBundle localizedStringForKey:@"USAGE_HEADER_CHARGE" value:nil table:@"BatteryUI"];
        if (s.length && ![s isEqualToString:@"USAGE_HEADER_CHARGE"]) return s;
    }
    return iebSegmentTitle();
}

#pragma mark - Last-charge parsing

// The pane's own query already fetched the "Last Charge" info
// (PLBatteryUIResponseTypeLastChargeLevel → currentLastChargeDictionary).
// Shape unknown at compile time, so probe defensively and log everything.
static NSDate *iebDateFromLastChargeDictionary(NSDictionary *dict) {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *timeKeys = @[@"lastChargeTimestamp", @"timestamp", @"lastChargedTimestamp", @"time", @"lastChargeTime"];
    for (NSString *key in timeKeys) {
        id v = dict[key];
        if ([v isKindOfClass:[NSDate class]]) return v;
        if ([v isKindOfClass:[NSNumber class]]) {
            double d = [v doubleValue];
            if (d > 1.0e9 && d < 6.0e9) return [NSDate dateWithTimeIntervalSince1970:d];
            if (d > 1.0e12 && d < 6.0e15) return [NSDate dateWithTimeIntervalSince1970:d / 1000.0];
        }
    }
    // nested shapes: {"PLBatteryUILastChargeKey": {...}} etc.
    for (NSString *key in dict) {
        id v = dict[key];
        if ([v isKindOfClass:[NSDictionary class]]) {
            NSDate *nested = iebDateFromLastChargeDictionary(v);
            if (nested) return nested;
        }
    }
    return nil;
}

#pragma mark - Segment control discovery

static UISegmentedControl *iebFindSegmentedControl(UIView *view) {
    if ([view isKindOfClass:[UISegmentedControl class]]) return (UISegmentedControl *)view;
    for (UIView *sub in view.subviews) {
        UISegmentedControl *hit = iebFindSegmentedControl(sub);
        if (hit) return hit;
    }
    return nil;
}

#pragma mark - Segment specifier patching (idempotent)

static NSString *iebTitleForValue(NSDictionary *titleDictionary, id value) {
    if (![titleDictionary isKindOfClass:[NSDictionary class]]) return nil;
    id hit = titleDictionary[value];
    if (hit) return [hit description];
    hit = titleDictionary[[value description]];
    if (hit) return [hit description];
    for (NSString *key in titleDictionary) {
        if ([key respondsToSelector:@selector(integerValue)] && [value respondsToSelector:@selector(integerValue)]
            && [key integerValue] == [value integerValue]) {
            return [titleDictionary[key] description];
        }
    }
    return nil;
}

static void iebEnsureSegmentSpecHasSLC(PSSpecifier *spec) {
    if (![spec isKindOfClass:NSClassFromString(@"PSSpecifier")]) return;

    // PLBatteryUISegmentCell is used only by the battery usage pane, so the
    // two-value segment it refreshes is always the Last 24 Hours / Last 10
    // Days control — no selector matching needed.
    NSArray *values = [spec values];
    const char *actionName = [spec action] ? sel_getName([spec action]) : "(none)";
    IEBLog(@"segmentCell spec=%@ action=%s values=%@ titles=%@",
           [spec name], actionName, values, [spec titleDictionary]);
    if (![values isKindOfClass:[NSArray class]]) return;
    if (values.count >= 3) return; // already patched
    if (values.count != 2) return; // not the day/week range control

    NSDictionary *titleDict = [spec titleDictionary];
    NSString *t0 = iebTitleForValue(titleDict, values.firstObject) ?: @"Last 24 Hours";
    NSString *t1 = iebTitleForValue(titleDict, values[1]) ?: @"Last 10 Days";

    NSMutableArray *newValues = [values mutableCopy];
    NSMutableArray *newTitles = [NSMutableArray arrayWithObject:t0];
    [newTitles addObject:t1];
    [newValues addObject:[NSNumber numberWithInt:2]];
    [newTitles addObject:iebSegmentTitle()];
    [spec setValues:newValues titles:newTitles];
    IEBLog(@"patched range specifier: values=%@ titles=%@", newValues, newTitles);
}

#pragma mark - SLC window computation

static void iebEnterSLCMode(BatteryUIController *controller) {
    NSDate *start = iebDateFromLastChargeDictionary([controller currentLastChargeDictionary]);
    if (!start) {
        IEBLog(@"no last-charge timestamp found — falling back to a 24h window. Dict: %@",
               [controller currentLastChargeDictionary]);
        start = [NSDate dateWithTimeIntervalSinceNow:-86400.0];
    }
    iebSLCWindowStart = start;
    double span = -[start timeIntervalSinceNow];
    if (span < 300.0) span = 300.0;                 // don't query razor-thin windows
    if (span > 864000.0) span = 864000.0;           // powerlog keeps ~10 days of detail
    iebSLCSpanSeconds = span;

    // Render with the Apple style closest to the window:
    //  ≤ 24h → day style (hourly buckets, 24-hour chart, hour labels)
    //  > 24h → week style (daily buckets, 10-day chart, day labels)
    iebSLCBaseRange = (span <= 86400.0) ? 0 : 1;
    iebSLCBucketSeconds = (iebSLCBaseRange == 0) ? 3600.0 : 86400.0;

    // The pane reads this ivar everywhere (chart identifier, label
    // formatting, tap handling) — keep it at the matching Apple style.
    iebSetIntIvar(controller, "_batteryUIQueryRange", iebSLCBaseRange);
    iebSLCSelected = YES;
    IEBLog(@"SLC mode: start=%@ span=%.0fs bucket=%.0fs style=%d",
           start, span, iebSLCBucketSeconds, iebSLCBaseRange);
}

// ===========================================================================
// Hooks
// ---------------------------------------------------------------------------
// BatteryUsageUI.bundle (all hooked classes) is loaded lazily when the user
// navigates to Settings > Battery — long after this dylib's constructor runs.
// So the hooks live in their own group and are installed from a dyld
// add-image callback the moment the bundle appears.
// ===========================================================================

%group IEBBatteryHooks

%hook BatteryUIController

// Every query pass goes through here; the payload is built synchronously
// inside, so while the SLC tab is active we keep the remap enabled.
- (void)queryForBatteryBreakdown {
    iebSLCQueryActive = iebSLCSelected;
    if (iebSLCQueryActive) {
        // keep the window fresh (a charge may have completed while the pane is open)
        double span = iebSLCWindowStart ? -[iebSLCWindowStart timeIntervalSinceNow] : 86400.0;
        if (span > 60.0 && span <= 864000.0) {
            iebSLCSpanSeconds = MAX(span, 300.0);
            iebSLCBaseRange = (iebSLCSpanSeconds <= 86400.0) ? 0 : 1;
            iebSLCBucketSeconds = (iebSLCBaseRange == 0) ? 3600.0 : 86400.0;
            iebSetIntIvar(self, "_batteryUIQueryRange", iebSLCBaseRange);
        }
    }
    %orig;
    iebSLCQueryActive = NO;
}

// The segment control's action. PS passes (value, specifier); detect the
// order defensively in case the convention ever differs.
- (void)setBatteryUIQueryRange:(id)arg1 specifier:(id)arg2 {
    id value = arg1;
    id spec = arg2;
    Class specClass = NSClassFromString(@"PSSpecifier");
    if (specClass && [value isKindOfClass:specClass]) {
        value = arg2;
        spec = arg1;
    }
    NSInteger newRange = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : -1;
    IEBLog(@"setBatteryUIQueryRange: value=%@ spec=%@ (SLC=%d)", value, [spec name], iebSLCSelected);

    if (newRange == 2) {
        // --- "Since Last Charge" selected ---
        iebEnterSLCMode(self);
        // Deliberately NOT calling %orig: it would persist range 2 into
        // Apple's day/week preference keys. We drive the reload ourselves.
        [self queryForBatteryBreakdown];
    } else {
        BOOL wasSLC = iebSLCSelected;
        iebSLCSelected = NO;
        iebSLCQueryActive = NO;
        %orig;
        if (wasSLC) {
            // our SLC query overwrote the pane's cached results — refetch
            // the day/week window through Apple's own pipeline.
            [self queryForBatteryBreakdown];
        }
    }
}

// Leaving/re-entering the pane re-runs the standard query (viewWillAppear
// calls queryForBatteryBreakdown), so drop SLC mode before that happens.
- (void)viewWillAppear:(BOOL)animated {
    if (iebSLCSelected) IEBLog(@"pane re-appearing — resetting SLC mode");
    iebSLCSelected = NO;
    iebSLCQueryActive = NO;
    %orig;
}

// Debug: observe what the powerlog pipeline hands to the UI.
- (void)setUpBatteryUIDictionary:(NSDictionary *)dict {
    if (iebDebugEnabled) {
        IEBLog(@"setUpBatteryUIDictionary keys: %@ (SLC=%d)", dict.allKeys, iebSLCSelected);
    }
    %orig;
}

%end

%hook PLBatteryUIBackendModel

// Remap every query window to [last charge … now] while the SLC tab is
// active. Apple builds the payload synchronously inside
// -[BatteryUIController queryForBatteryBreakdown], so this covers all 17+
// query types (breakdown, usage times, battery levels, charging intervals,
// last charge level, suggestions, …) with one consistent window.
- (void)addQueryType:(long)type withEndDate:(id)endDate withRange:(double)range withBucketSize:(double)bucketSize {
    if (iebSLCQueryActive) {
        IEBLog(@"remap type=%ld endDate=%@ range=%.0fs bucket=%.0fs → SLC span=%.0fs bucket=%.0fs",
               type, endDate, range, bucketSize, iebSLCSpanSeconds, iebSLCBucketSeconds);
        endDate = [NSDate date];
        range = iebSLCSpanSeconds;
        bucketSize = iebSLCBucketSeconds;
    }
    %orig(type, endDate, range, bucketSize);
}

%end

%hook PLBatteryUISegmentCell

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    iebEnsureSegmentSpecHasSLC(specifier);
    %orig;

    // If the pane rebuilt the specifier list it resets the segment value
    // from Apple's preferences — visually re-select the SLC tab.
    if (iebSLCSelected) {
        UISegmentedControl *control = iebFindSegmentedControl(self);
        if (control && control.numberOfSegments >= 3) {
            if (control.selectedSegmentIndex != 2) {
                [control setSelectedSegmentIndex:2];
                IEBLog(@"forced segment selection to 2");
            }
            // three localized titles need a slightly smaller font than the
            // 2-segment fit Apple computed
            UIFont *fitted = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
            [control setTitleTextAttributes:@{NSFontAttributeName: fitted} forState:UIControlStateNormal];
        }
    }
}

- (UIFont *)getFittingPreferredFontFromSegment1:(NSString *)s1 andSegment2:(NSString *)s2 {
    UIFont *font = %orig;
    NSArray *values = nil;
    // shrink only once the third segment actually exists
    Class specClass = NSClassFromString(@"PSSpecifier");
    if (specClass && [self respondsToSelector:@selector(specifier)]) {
        id spec = [self performSelector:@selector(specifier)];
        if ([spec isKindOfClass:specClass]) values = [spec values];
    }
    if ([values isKindOfClass:[NSArray class]] && values.count >= 3) {
        CGFloat size = MAX(9.0, font.pointSize * 0.86);
        font = [font fontWithSize:size];
        IEBLog(@"shrunk segment font to %.1f (3 segments)", size);
    }
    return font;
}

%end

%hook PLBatteryUIBatteryGroupHeader

// The group header ("BATTERY USAGE — LAST 24 HOURS") is driven by the range;
// relabel it for the SLC window.
- (void)setRange:(id)range {
    %orig;
    if (iebSLCSelected) {
        iebSetObjectIvar(self, "_rangeString", iebSegmentTitle());
        IEBLog(@"group header relabeled for SLC");
    }
}

%end

%end // group IEBBatteryHooks

// ---------------------------------------------------------------------------
// Lazy hook installation
// ---------------------------------------------------------------------------

static BOOL iebHooksInstalled = NO;

static void iebInstallBatteryHooks(void) {
    if (iebHooksInstalled) return;
    if (!NSClassFromString(@"BatteryUIController")) return;
    %init(IEBBatteryHooks);
    iebHooksInstalled = YES;
    IEBLog(@"battery pane hooks installed");
}

static void iebImageAdded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (dladdr((const void *)mh, &info) && info.dli_fname
        && strstr(info.dli_fname, "BatteryUsageUI")) {
        // dispatch to the main queue: ObjC class registration for the image
        // completes before the queued block runs
        dispatch_async(dispatch_get_main_queue(), ^{ iebInstallBatteryHooks(); });
    }
}

%ctor {
    @try {
        CFBooleanRef flag = NULL;
        if (&CFPreferencesCopyAppValue) {
            flag = (CFBooleanRef)CFPreferencesCopyAppValue(CFSTR("Debug"), CFSTR("com.idonamaan.iosextendbattery"));
        }
        iebDebugEnabled = (flag && CFBooleanGetValue(flag));
        if (flag) CFRelease(flag);
    } @catch (NSException *e) {
        iebDebugEnabled = NO;
    }
    IEBLogRaw(@"iOSExtendBattery loaded (debug=%d) in %@", iebDebugEnabled, [[NSBundle mainBundle] bundleIdentifier]);
    _dyld_register_func_for_add_image(iebImageAdded);
    iebInstallBatteryHooks(); // in case the bundle is somehow already loaded
}
