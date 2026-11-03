#import "../Sources/Diagnostics/IEBDiagnosticReport.h"
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Readable report FAIL %d\n", __LINE__);                                          \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSString *canary = @"PRIVATE_NAME_PID_PATH";
        NSDictionary *model = @{
            @"state" : @"incomplete",
            @"range" : @{@"start" : @100, @"end" : @400},
            @"window" : @{
                @"start" : @100,
                @"end" : @400,
                @"epoch" : @"old",
                @"current_epoch" : @"new",
                @"power_complete" : @NO
            },
            @"activity_latest_end" : @160,
            @"screen_on" : @250,
            @"screen_off" : NSNull.null,
            @"apps" : @[ @{@"id" : canary} ],
            @"energy_total" : @10,
            @"energy_retention_incomplete" : @YES,
            @"levels" : @[],
            @"source_error" : canary
        };
        NSDictionary *snapshot = @{
            @"reader_provider" : @"root-service",
            @"status" : @"partial",
            @"rows" : @[ @{@"name" : canary} ],
            @"permission_denied_count" : @0,
            @"vanished_count" : @2,
            @"name_unavailable_count" : @1,
            @"enumeration_truncated" : @YES,
            @"reader_failure" : canary
        };
        NSString *text = IEBReadableDiagnosticReportInLanguage(model, snapshot, @"he");
        C([text containsString:@"דוח אבחון סוללה"] && [text containsString:@"נתונים חלקיים"]);
        C([text containsString:@"זמן מסך: 00:04:10"] && [text containsString:@"שימוש כשהמסך כבוי: לא זמין"]);
        C([text containsString:@"00:01:00"] && [text containsString:@"00:04:00"]);
        C([text containsString:@"קריאה בהרשאות root"] && [text containsString:@"נעלמו בזמן הדגימה: 2"]);
        C([text containsString:@"שוחזר עד נקודת השמירה"] && ![text containsString:canary]);
        NSString *unknown = IEBReadableDiagnosticReportInLanguage(nil, nil, @"he");
        C([unknown containsString:@"הנתונים אינם זמינים"] &&
          [unknown containsString:@"תהליכים זמינים: לא זמין"]);
        C([unknown containsString:@"הרשאות מוגבלות"]);
        NSError *error = nil;
        NSDictionary *json =
            [NSJSONSerialization JSONObjectWithData:IEBDiagnosticReport(model, snapshot, &error)
                                            options:0
                                              error:&error];
        C([json[@"screen_on_seconds"] isEqual:@250] && [json[@"quality"][@"pending_seconds"] isEqual:@240]);
        NSMutableDictionary *complete = [model mutableCopy];
        complete[@"state"] = @"observed";
        complete[@"window"] = @{@"start" : @100, @"power_complete" : @YES};
        complete[@"activity_latest_end"] = @400;
        complete[@"energy_retention_incomplete"] = @NO;
        complete[@"energy_coverage_known"] = @YES;
        complete[@"levels"] = @[ @{@"time" : @100, @"level" : @80} ];
        [complete removeObjectForKey:@"source_error"];
        NSString *current = IEBReadableDiagnosticReportInLanguage(
            complete,
            @{@"reader_provider" : @"root-service",
              @"status" : @"available",
              @"rows" : @[]},
            @"he");
        C([current containsString:@"הרישום הכללי הגיע לסוף הטווח"] &&
          [current containsString:@"רשומות הצריכה משתרעות על הטווח"]);
        C([current containsString:@"תמונת התהליכים: זמינה"] && ![current containsString:@"נתונים חלקיים"]);
        puts("PASS readable Hebrew report preserves unavailable states, units and aggregate privacy");
        return 0;
    }
}
