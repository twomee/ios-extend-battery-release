#import "../Sources/Diagnostics/IEBDiagnosticReport.h"
#import "../Sources/Localization/IEBLocalization.h"
#import <Foundation/Foundation.h>
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Report FAIL %d\n", __LINE__);                                                   \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSString *canary = @"PRIVATE_CANARY/app.name/pid999/path/epoch";
        NSData *data = IEBDiagnosticReport(
            @{
                @"state" : @"observed",
                @"range" : @{@"start" : @100, @"end" : @400},
                @"window" : @{@"start" : @100, @"epoch" : canary},
                @"apps" : @[ @{@"id" : canary} ],
                @"source_error" : canary,
                @"energy_error" : canary,
                @"activity_latest_end" : @160,
                @"screen_on" : @250,
                @"screen_off" : @(-1)
            },
            @{
                @"reader_provider" : @"root-service",
                @"status" : @"partial",
                @"rows" : @[
                    @{@"name" : canary,
                      @"pid" : @999}
                ],
                @"reader_failure" : canary
            },
            &error);
        C(data && !error);
        NSDictionary *r = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        C(r && !error && [r[@"schema"] isEqual:@1]);
        C([r[@"quality"][@"pending_seconds"] isEqual:@240]);
        C([r[@"screen_on_seconds"] isEqual:@250] && r[@"screen_off_seconds"] == NSNull.null);
        C([r[@"app_source_count"] isEqual:@1] && [r[@"process_reader"][@"readable"] isEqual:@1]);
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        C(![json containsString:canary] && !r[@"range"] && !r[@"apps"] && !r[@"window"]);
        data = IEBDiagnosticReport(nil, nil, &error);
        C(data && !error);
        r = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        C([r[@"quality"][@"state"] isEqual:@"unavailable"]);
        C(r[@"screen_on_seconds"] == NSNull.null && r[@"app_source_count"] == NSNull.null);
        NSString *automatic = IEBReadableDiagnosticReport(nil, nil);
        NSString *chosen = IEBCurrentLanguage();
        C([automatic isEqual:IEBReadableDiagnosticReportInLanguage(nil, nil, chosen)]);
        NSDictionary *model = @{
            @"state" : @"observed",
            @"range" : @{@"start" : @100, @"end" : @400},
            @"activity_latest_end" : @400,
            @"screen_on" : @0,
            @"screen_off" : NSNull.null,
            @"energy_total" : @10,
            @"energy_coverage_known" : @YES,
            @"levels" : @[
                @{@"time" : @100,
                  @"level" : @80}
            ],
            @"apps" : @[ @{@"id" : canary} ]
        };
        NSDictionary *snapshot = @{
            @"reader_provider" : @"root-service",
            @"status" : @"available",
            @"rows" : @[ @{@"name" : canary} ],
            @"permission_denied_count" : @0
        };
        for (NSString *language in @[ @"en", @"he", @"HE-il", @"iw", @"zz" ]) {
            BOOL he = [@[ @"he", @"HE-il", @"iw" ] containsObject:language];
            NSString *text = IEBReadableDiagnosticReportInLanguage(model, snapshot, language);
            C([text containsString:he ? @"דוח אבחון סוללה" : @"Battery diagnostic report"]);
            C([text containsString:he ? @"זמן מסך: 00:00:00" : @"Screen on: 00:00:00"]);
            C([text containsString:he ? @"שימוש כשהמסך כבוי: לא זמין" : @"Screen off usage: Unavailable"]);
            C([text containsString:he ? @"הרישום הכללי הגיע לסוף הטווח"
                                      : @"Overall recording reached the end of the range"]);
            C([text
                containsString:he ? @"רשומות הצריכה משתרעות על הטווח" : @"Energy records span the range"]);
            C([text containsString:he ? @"תמונת התהליכים: זמינה" : @"Process snapshot: Available"]);
            C([text containsString:he ? @"ללא הרשאת קריאה: 0" : @"Permission denied: 0"]);
            C(![text containsString:canary]);
            NSString *unknown = IEBReadableDiagnosticReportInLanguage(nil, nil, language);
            C([unknown containsString:he ? @"הנתונים אינם זמינים" : @"Data is unavailable"]);
            C([unknown containsString:he ? @"תהליכים זמינים: לא זמין" : @"Readable processes: Unavailable"]);
            NSMutableDictionary *partial = [model mutableCopy];
            partial[@"activity_latest_end"] = @160;
            partial[@"energy_coverage_known"] = @NO;
            partial[@"window"] =
                @{@"end" : @400,
                  @"power_complete" : @NO,
                  @"epoch" : @"old",
                  @"current_epoch" : @"new"};
            NSString *textPartial = IEBReadableDiagnosticReportInLanguage(
                partial, @{@"status" : @"partial", @"reader_failure" : @"service-timeout"}, language);
            C([textPartial containsString:he ? @"נתונים חלקיים" : @"Partial data"]);
            C([textPartial containsString:he ? @"רישום חלקי או כיסוי לא ידוע"
                                             : @"Partial recording or unknown coverage"]);
            C([textPartial containsString:he ? @"תמונת התהליכים: חלקית" : @"Process snapshot: Partial"]);
            C([textPartial containsString:he ? @"שירות root לא השיב בזמן" : @"Root service timed out"]);
            C([textPartial containsString:he ? @"שוחזר עד נקודת השמירה" : @"recovered up to the last save"]);
            NSString *denied =
                IEBReadableDiagnosticReportInLanguage(nil, @{@"reader_failure" : @"caller-denied"}, language);
            C([denied containsString:he ? @"אימות הקורא נדחה" : @"Reader authentication was denied"]);
        }
        puts("PASS diagnostic JSON allowlist excludes identities, paths, PIDs, raw errors and timestamps");
        return 0;
    }
}
