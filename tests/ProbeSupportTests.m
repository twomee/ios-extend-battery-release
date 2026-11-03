#import "../tools/IEBProbeSupport.h"

static unsigned checks;
#define CHECK(condition)                                                                                     \
    do {                                                                                                     \
        checks++;                                                                                            \
        if (!(condition)) {                                                                                  \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition);                                     \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)

int IEBRunProducerEvidenceTests(void);

int main(void) {
    @autoreleasepool {
        // Catches treating a missing response as a successful zero-usage query.
        NSDictionary *empty = IEBSummarizeResponse(nil);
        CHECK([empty[@"response_present"] isEqual:@NO]);
        CHECK([empty[@"app_count"] isEqual:[NSNull null]]);
        CHECK([IEBFeasibilityDecision(empty, empty) isEqual:@"reference-unavailable"]);
        CHECK([IEBSummarizeResponse(@[]) isEqual:empty]);
        CHECK([IEBSummarizeResponse(@{})[@"response_present"] isEqual:@NO]);

        NSDictionary *native = @{
            @"Breakdown" : @{
                @"PLBatteryUIQueryRangeDayKey" : @{
                    @"PLBatteryUIAppArrayKey" : @[ @{@"PLBatteryUIAppBundleIDKey" : @"private.app"} ],
                    @"PLBatteryUIForegroundTimeKey" : @120,
                    @"PLBatteryUIBackgroundTimeKey" : @30,
                },
                @"PLBatteryUIQueryRangeDayTapKey" : @[ @{} ],
            },
            @"Graph" : @{
                @"PLBatteryUIGraph24hrs" : @{
                    @"PLBatteryUIBatteryLevelsKey" : @[ @{} ],
                    @"PLBatteryUIScreenOnTimeKey" : @{@"PLBatteryUIGraphHourly" : @[ @{} ]},
                }
            },
        };
        NSDictionary *summary = IEBSummarizeResponse(native);
        CHECK([summary[@"response_present"] isEqual:@YES]);
        CHECK([summary[@"app_count"] isEqual:@1]);
        CHECK([summary[@"foreground_seconds"] isEqual:@120]);
        CHECK([summary[@"background_seconds"] isEqual:@30]);
        CHECK([summary[@"hour_count"] isEqual:@1]);
        CHECK([summary[@"has_level_graph"] isEqual:@YES]);
        CHECK([summary[@"has_activity_graph"] isEqual:@YES]);
        CHECK([IEBFeasibilityDecision(summary, summary) isEqual:@"boundary-validation-required"]);
        NSMutableDictionary *noDrilldown = [summary mutableCopy];
        noDrilldown[@"hour_count"] = [NSNull null];
        CHECK([IEBFeasibilityDecision(summary, noDrilldown) isEqual:@"missing-scoped-components"]);
        // Counts do not constitute proof of a correct arbitrary-range result.
        CHECK(![[summary description] containsString:@"private.app"]);
        CHECK(![[summary description] containsString:@"PLBatteryUIAppBundleIDKey"]);

        NSDictionary *narrow = IEBSummarizeResponse(@{
            @"Breakdown" : @{@"PLBatteryUIDataDurationKey" : @3600},
            @"Graph" : @{@"PLBatteryUIGraph24hrs" : @{}},
        });
        CHECK([narrow[@"app_count"] isEqual:[NSNull null]]);
        CHECK([narrow[@"foreground_seconds"] isEqual:[NSNull null]]);
        CHECK([IEBFeasibilityDecision(summary, narrow) isEqual:@"missing-scoped-components"]);

        // Malformed time fields must not become zeros or nonfinite JSON.
        NSDictionary *malformed = IEBSummarizeResponse(@{
            @"Breakdown" : @{
                @"PLBatteryUIQueryRangeDayKey" : @{
                    @"PLBatteryUIAppArrayKey" : @"bad",
                    @"PLBatteryUIForegroundTimeKey" : @YES,
                    @"PLBatteryUIBackgroundTimeKey" : @(-1),
                }
            },
            @"Graph" : [NSNull null],
        });
        CHECK([malformed[@"app_count"] isEqual:[NSNull null]]);
        CHECK([malformed[@"foreground_seconds"] isEqual:[NSNull null]]);
        CHECK([malformed[@"background_seconds"] isEqual:[NSNull null]]);
        CHECK([malformed[@"has_level_graph"] isEqual:@NO]);
        CHECK([NSJSONSerialization isValidJSONObject:malformed]);
        NSDictionary *nonfinite = IEBSummarizeResponse(@{
            @"Breakdown" : @{@"PLBatteryUIQueryRangeDayKey" : @{@"PLBatteryUIForegroundTimeKey" : @(NAN)}}
        });
        CHECK([nonfinite[@"foreground_seconds"] isEqual:[NSNull null]]);
        NSDictionary *window = IEBParseQueryWindow(@"1000.25", @"2237.5");
        CHECK([window[@"span"] isEqual:@1237.25]);
        CHECK(IEBParseQueryWindow(@"1000;exit", @"2237") == nil);
        CHECK(IEBParseQueryWindow(@"nan", @"2237") == nil);
        CHECK(IEBParseQueryWindow(@"1000", @"inf") == nil);
        CHECK(IEBParseQueryWindow(@"1000", @"1000") == nil);
        CHECK(IEBParseQueryWindow(@"1000", @"999") == nil);
        CHECK(IEBParseQueryWindow(@"0", @"2237") == nil);
        CHECK(IEBParseQueryWindow(@" 1000", @"2237") == nil);
        CHECK(IEBParseQueryWindow(@"1000", @"999999") == nil);
        CHECK(IEBParseQueryWindow(nil, @"2237") == nil);
        CHECK(IEBRunProducerEvidenceTests() == 0);
        printf("PASS %u checks\n", checks);
    }
    return 0;
}
