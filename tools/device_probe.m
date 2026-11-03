// Diagnostic only. No injection, installation, history resets or charge changes.
#import "IEBProbeSupport.h"
#import "IEBProducerEvidence.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSDictionary *PowerState(void) {
    void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!io)
        return @{@"available" : @NO};
    CFTypeRef (*copyInfo)(void) = dlsym(io, "IOPSCopyPowerSourcesInfo");
    CFArrayRef (*copyList)(CFTypeRef) = dlsym(io, "IOPSCopyPowerSourcesList");
    CFDictionaryRef (*description)(CFTypeRef, CFTypeRef) = dlsym(io, "IOPSGetPowerSourceDescription");
    if (!copyInfo || !copyList || !description)
        return @{@"available" : @NO};
    CFTypeRef info = copyInfo();
    CFArrayRef list = info ? copyList(info) : NULL;
    NSDictionary *result = @{@"available" : @NO};
    for (id source in (__bridge NSArray *)list) {
        NSDictionary *row = (__bridge NSDictionary *)description(info, (__bridge CFTypeRef)source);
        if (![row[@"Type"] isEqual:@"InternalBattery"])
            continue;
        NSString *state = row[@"Power Source State"];
        result = @{
            @"available" : @YES,
            @"external_power" : [state isEqual:@"AC Power"] ? @YES
            : [state isEqual:@"Battery Power"]              ? @NO
                                                            : (id)[NSNull null],
            @"charging" : [row[@"Is Charging"] isKindOfClass:[NSNumber class]]
                ? @([row[@"Is Charging"] boolValue])
                : (id)[NSNull null],
        };
        break;
    }
    if (list)
        CFRelease(list);
    if (info)
        CFRelease(info);
    return result;
}

static NSDictionary *QueryWithUsageBucket(Class cls, NSDate *end, double span, BOOL producer,
                                          double usageBucket) {
    id model = [cls new];
    SEL add = NSSelectorFromString(@"addQueryType:withEndDate:withRange:withBucketSize:");
    // Native day-style requests, with an additional hourly app breakdown.
    // Remapping is the existing tweak's proposed mechanism, being tested here.
    for (NSNumber *type in @[ @0, @1, @5, @7, @8 ]) {
        double bucket = type.intValue == 7 ? 900 : type.intValue == 8 ? usageBucket : span;
        ((id(*)(id, SEL, long, id, double, double))objc_msgSend)(model, add, type.longValue, end, span,
                                                                 bucket);
    }
    ((id(*)(id, SEL, long, id, double, double))objc_msgSend)(model, add, 1, end, span, 3600.0);
    if (producer) {
        NSMutableDictionary *payload =
            ((id(*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"queryPayload"));
        for (id key in [payload allKeys]) {
            if (![payload[key] isKindOfClass:[NSDictionary class]])
                continue;
            NSMutableDictionary *request = [payload[key] mutableCopy];
            request[@"IEBProbeVersion"] = @1;
            payload[key] = request;
        }
    }
    ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"addSkipPlistWriteKey"));
    ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"runQuery"));
    id response = ((id(*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"queryResult"));
    return @{
        @"requested_start" : @([end timeIntervalSince1970] - span),
        @"requested_end" : @([end timeIntervalSince1970]),
        @"requested_seconds" : @(span),
        @"summary" : IEBSummarizeResponse(response),
        @"producer_evidence" : producer
            ? IEBSanitizeProducerEvidence(
                  [response isKindOfClass:[NSDictionary class]] ? response[@"IEBProducerEvidence"] : nil)
            : @{@"available" : @NO},
    };
}

static NSDictionary *Query(Class cls, NSDate *end, double span, BOOL producer) {
    return QueryWithUsageBucket(cls, end, span, producer, 3600);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL explicitWindow = argc == 4 && strcmp(argv[1], "--producer-window") == 0;
        NSDictionary *window = explicitWindow ? IEBParseQueryWindow([NSString stringWithUTF8String:argv[2]],
                                                                    [NSString stringWithUTF8String:argv[3]])
                                              : nil;
        if ((explicitWindow && !window) ||
            (!explicitWindow && (argc > 2 || (argc == 2 && (strcmp(argv[1], "--query") != 0 &&
                                                            strcmp(argv[1], "--producer-query") != 0 &&
                                                            strcmp(argv[1], "--producer-matrix") != 0))))) {
            fprintf(stderr, "Usage: ieb-probe [--query|--producer-query|--producer-matrix] or "
                            "--producer-window START END\n");
            return 64;
        }
        NSMutableDictionary *report = [@{@"schema_version" : @1, @"power" : PowerState()} mutableCopy];
        NSDictionary *system =
            [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
        NSString *version = system[@"ProductVersion"];
        NSString *build = system[@"ProductBuildVersion"];
        report[@"version"] = version ?: @"unknown";
        report[@"build"] = build ?: @"unknown";
        int status = 0;
        @try {
            void *bundle =
                dlopen("/System/Library/PreferenceBundles/BatteryUsageUI.bundle/BatteryUsageUI", RTLD_NOW);
            NSMutableDictionary *settingsABI = [NSMutableDictionary new];
            for (NSArray *check in @[
                     @[ @"BatteryUIController", @"setBatteryUIQueryRange:specifier:", @"v32@0:8@16@24" ],
                     @[ @"PLBatteryUISegmentCell", @"refreshCellContentsWithSpecifier:", @"v24@0:8@16" ],
                     @[ @"PSSpecifier", @"setValues:titles:", @"v32@0:8@16@24" ]
                 ]) {
                Method method =
                    class_getInstanceMethod(NSClassFromString(check[0]), NSSelectorFromString(check[1]));
                settingsABI[check[0]] =
                    @(method && strcmp(method_getTypeEncoding(method), [check[2] UTF8String]) == 0);
            }
            report[@"settings_abi_matches"] = settingsABI;
            Class cls = NSClassFromString(@"PLBatteryUIBackendModel");
            NSDictionary *required = @{
                @"addQueryType:withEndDate:withRange:withBucketSize:" : @"@48@0:8q16@24d32d40",
                @"runQuery" : @"v16@0:8",
                @"addSkipPlistWriteKey" : @"v16@0:8",
                @"queryResult" : @"@16@0:8",
                @"queryPayload" : @"@16@0:8",
            };
            BOOL abi = bundle && cls;
            for (NSString *selector in required) {
                Method method = class_getInstanceMethod(cls, NSSelectorFromString(selector));
                abi = abi && method &&
                      strcmp(method_getTypeEncoding(method), [required[selector] UTF8String]) == 0;
            }
            BOOL target = [version isEqual:@"17.1.1"] && [build isEqual:@"21B91"];
            report[@"abi_matches"] = @(abi);
            if (!abi || !target) {
                report[@"decision"] = @"unsupported-target-or-abi";
                status = 21;
            } else if (explicitWindow) {
                NSDate *end = [NSDate dateWithTimeIntervalSince1970:[window[@"end"] doubleValue]];
                double span = [window[@"span"] doubleValue];
                report[@"window"] = QueryWithUsageBucket(cls, end, span, YES, span);
                report[@"producer_requested"] = @YES;
                report[@"decision"] = @"explicit-window-boundary-validation-required";
                status = 22;
            } else if (argc == 2 && strcmp(argv[1], "--producer-matrix") == 0) {
                NSDate *now = [NSDate date];
                NSMutableArray *windows = [NSMutableArray array];
                // Fixed bounded read-only experiment: recent and historical windows.
                // Historical windows distinguish unavailable recent aggregates from
                // unsupported arbitrary spans. No caller-supplied remote arguments.
                for (NSDictionary *window in @[
                         @{@"span" : @1237,
                           @"offset" : @0},
                         @{@"span" : @4837,
                           @"offset" : @0},
                         @{@"span" : @21637,
                           @"offset" : @0},
                         @{@"span" : @1237,
                           @"offset" : @7200},
                         @{@"span" : @4837,
                           @"offset" : @7200},
                         @{@"span" : @86400,
                           @"offset" : @7200}
                     ]) {
                    NSDate *end = [now dateByAddingTimeInterval:-[window[@"offset"] doubleValue]];
                    double span = [window[@"span"] doubleValue];
                    NSMutableDictionary *observation = [Query(cls, end, span, YES) mutableCopy];
                    observation[@"whole_window_usage"] = QueryWithUsageBucket(cls, end, span, YES, span);
                    [windows addObject:observation];
                }
                report[@"producer_requested"] = @YES;
                report[@"windows"] = windows;
                report[@"decision"] = @"producer-matrix-boundary-validation-required";
                status = 22;
            } else if (argc == 2) {
                BOOL producer = strcmp(argv[1], "--producer-query") == 0;
                report[@"producer_requested"] = @(producer);
                NSDate *end = [NSDate date];
                NSDictionary *reference = Query(cls, end, 86400, producer);
                NSDictionary *scoped = Query(cls, end, 1237, producer);
                NSDictionary *shortWindow = Query(cls, end, 0.25, producer);
                report[@"reference"] = reference;
                report[@"scoped"] = scoped;
                report[@"subsecond"] = shortWindow;
                NSString *scopedDecision = IEBFeasibilityDecision(reference[@"summary"], scoped[@"summary"]);
                NSString *shortDecision =
                    IEBFeasibilityDecision(reference[@"summary"], shortWindow[@"summary"]);
                report[@"scoped_decision"] = scopedDecision;
                report[@"subsecond_decision"] = shortDecision;
                report[@"decision"] =
                    [shortDecision isEqual:@"missing-scoped-components"] ? shortDecision : scopedDecision;
                // Structural completeness cannot certify exact boundary semantics.
                status = [report[@"decision"] isEqual:@"missing-scoped-components"] ? 20 : 22;
            } else {
                report[@"decision"] = @"queries-not-run";
            }
        } @catch (NSException *exception) {
            (void)exception;
            report[@"decision"] = @"probe-exception";
            status = 23;
        }
        NSError *error = nil;
        NSData *json =
            [NSJSONSerialization dataWithJSONObject:report
                                            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                              error:&error];
        if (!json) {
            fprintf(stderr, "Cannot encode diagnostic report\n");
            return 74;
        }
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return status;
    }
}
