#import "IEBDiagnosticReport.h"
#import "../Statistics/IEBDataQuality.h"
#import "IEBProcessReaderStatus.h"
#import <math.h>
static id Seconds(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
                   isfinite([n doubleValue]) && [n doubleValue] >= 0 && [n doubleValue] <= 86400000
               ? n
               : NSNull.null;
}
static NSDictionary *Summary(NSDictionary *model, NSDictionary *snapshot) {
    return @{
        @"schema" : @1,
        @"tweak_version" : @"0.2.22",
        @"quality" : IEBDataQuality(model),
        @"process_reader" : IEBProcessReaderStatus(snapshot),
        @"screen_on_seconds" : Seconds(model[@"screen_on"]),
        @"screen_off_seconds" : Seconds(model[@"screen_off"]),
        @"app_source_count" : [model[@"apps"] isKindOfClass:NSArray.class] ? @([model[@"apps"] count])
                                                                           : NSNull.null,
        @"energy_is_estimated" : @([model[@"allocation_estimated"] boolValue]),
        @"cpu_is_process_lifetime" : @YES
    };
}
NSData *IEBDiagnosticReport(NSDictionary *model, NSDictionary *snapshot, NSError **error) {
    if (error)
        *error = nil;
    return [NSJSONSerialization dataWithJSONObject:Summary(model, snapshot)
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:error];
}
static BOOL Hebrew(NSString *language) {
    NSString *code = [[language lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSString *base = [code componentsSeparatedByString:@"-"].firstObject;
    return [base isEqual:@"he"] || [base isEqual:@"iw"];
}
static NSString *Text(NSString *english, NSString *hebrewText, BOOL hebrew) {
    return hebrew ? hebrewText : english;
}
static NSString *ReportDuration(id value, BOOL hebrew) {
    id checked = Seconds(value);
    if (checked == NSNull.null)
        return Text(@"Unavailable", @"לא זמין", hebrew);
    NSInteger seconds = (NSInteger)round([checked doubleValue]);
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)(seconds / 3600), (long)(seconds / 60 % 60),
                                      (long)(seconds % 60)];
}
static NSString *Count(id value, BOOL hebrew) {
    return [value isKindOfClass:NSNumber.class] ? [value description]
                                                : Text(@"Unavailable", @"לא זמין", hebrew);
}
NSString *IEBReadableDiagnosticReportInLanguage(NSDictionary *model, NSDictionary *snapshot,
                                                NSString *language) {
    BOOL hebrew = Hebrew(language);
    NSDictionary *report = Summary(model, snapshot), *quality = report[@"quality"],
                 *reader = report[@"process_reader"];
    NSString *state =
        [quality[@"state"] isEqual:@"recorded"]
            ? Text(@"Overall recording reached the end of the range; per-app coverage is not guaranteed",
                   @"הרישום הכללי הגיע לסוף הטווח; הכיסוי לכל אפליקציה אינו מובטח", hebrew)
        : [quality[@"state"] isEqual:@"partial"]
            ? Text(@"Partial data; totals may change", @"נתונים חלקיים; הסכומים עשויים להשתנות", hebrew)
            : Text(@"Data is unavailable", @"הנתונים אינם זמינים", hebrew);
    NSString *energy =
        [quality[@"energy_state"] isEqual:@"recorded"]
            ? Text(@"Energy records span the range", @"רשומות הצריכה משתרעות על הטווח", hebrew)
        : [quality[@"energy_state"] isEqual:@"partial"]
            ? Text(@"Partial recording or unknown coverage", @"רישום חלקי או כיסוי לא ידוע", hebrew)
            : Text(@"Unavailable", @"לא זמין", hebrew);
    BOOL root = [reader[@"provider"] isEqual:@"root"];
    NSString *readerState = [reader[@"state"] isEqual:@"available"] ? Text(@"Available", @"זמינה", hebrew)
                            : [reader[@"state"] isEqual:@"partial"]
                                ? Text(@"Partial", @"חלקית", hebrew)
                                : Text(@"Unavailable", @"לא זמינה", hebrew);
    NSString *reason =
        root ? Text(@"Received a response from the root reader", @"התקבלה תשובה מקורא root", hebrew)
        : [reader[@"reason"] isEqual:@"caller-denied"]
            ? Text(@"Reader authentication was denied", @"אימות הקורא נדחה", hebrew)
        : [reader[@"reason"] isEqual:@"service-timeout"]
            ? Text(@"Root service timed out", @"שירות root לא השיב בזמן", hebrew)
            : Text(@"Root service is unavailable or its response is invalid",
                   @"שירות root אינו זמין או שתשובתו אינה תקינה", hebrew);
    return [@[
        Text(@"Battery diagnostic report — Since Unplugged", @"דוח אבחון סוללה — מאז הניתוק", hebrew),
        [Text(@"Tweak version: ", @"גרסת הטוויק: ", hebrew) stringByAppendingString:report[@"tweak_version"]],
        @"",
        [Text(@"Data status: ", @"מצב הנתונים: ", hebrew) stringByAppendingString:state],
        [Text(@"Range duration: ", @"משך הטווח: ", hebrew)
            stringByAppendingString:ReportDuration(quality[@"range_seconds"], hebrew)],
        [Text(@"Screen on: ", @"זמן מסך: ", hebrew)
            stringByAppendingString:ReportDuration(report[@"screen_on_seconds"], hebrew)],
        [Text(@"Screen off usage: ", @"שימוש כשהמסך כבוי: ", hebrew)
            stringByAppendingString:ReportDuration(report[@"screen_off_seconds"], hebrew)],
        [NSString stringWithFormat:Text(@"Activity recorded up to %@ from the start of the range",
                                        @"פעילות נרשמה עד %@ מתחילת הטווח", hebrew),
                                   ReportDuration(quality[@"activity_recorded_seconds"], hebrew)],
        [Text(@"Time awaiting activity recording: ", @"זמן שממתין לרישום פעילות: ", hebrew)
            stringByAppendingString:ReportDuration(quality[@"pending_seconds"], hebrew)],
        [Text(@"Energy data: ", @"נתוני צריכה: ", hebrew) stringByAppendingString:energy],
        [Text(@"Battery level records: ", @"רישומי רמת סוללה: ", hebrew)
            stringByAppendingString:[quality[@"levels_available"] boolValue]
                                        ? Text(@"Available", @"זמינים", hebrew)
                                        : Text(@"Unavailable", @"לא זמינים", hebrew)],
        [Text(@"App source count: ", @"מספר מקורות אפליקציות: ", hebrew)
            stringByAppendingString:Count(report[@"app_source_count"], hebrew)],
        [quality[@"recovered_cycle"] boolValue]
            ? Text(@"The cycle was recovered up to the last save; the time after it is unknown.",
                   @"המחזור שוחזר עד נקודת השמירה האחרונה; הזמן שאחריה אינו ידוע.", hebrew)
            : @"",
        @"",
        Text(@"Process reading", @"קריאת תהליכים", hebrew),
        root ? Text(@"Data provider: Root access", @"ספק הנתונים: קריאה בהרשאות root", hebrew)
             : Text(@"Data provider: Limited permissions", @"ספק הנתונים: הרשאות מוגבלות", hebrew),
        [Text(@"Process snapshot: ", @"תמונת התהליכים: ", hebrew) stringByAppendingString:readerState],
        [Text(@"Readable processes: ", @"תהליכים זמינים: ", hebrew)
            stringByAppendingString:Count(reader[@"readable"], hebrew)],
        [Text(@"Permission denied: ", @"ללא הרשאת קריאה: ", hebrew)
            stringByAppendingString:Count(reader[@"denied"], hebrew)],
        [Text(@"Vanished during sampling: ", @"נעלמו בזמן הדגימה: ", hebrew)
            stringByAppendingString:Count(reader[@"vanished"], hebrew)],
        [Text(@"Unnamed processes: ", @"תהליכים ללא שם: ", hebrew)
            stringByAppendingString:Count(reader[@"unnamed"], hebrew)],
        [Text(@"List truncated: ", @"הרשימה נקטעה: ", hebrew)
            stringByAppendingString:[reader[@"truncated"] boolValue] ? Text(@"Yes", @"כן", hebrew)
                                                                     : Text(@"No", @"לא", hebrew)],
        [Text(@"Root service status: ", @"מצב שירות root: ", hebrew) stringByAppendingString:reason],
        @"",
        Text(@"How to interpret the data", @"איך לפרש את הנתונים", hebrew),
        Text(@"All times use hours:minutes:seconds. Unavailable data is not zero.",
             @"כל הזמנים מוצגים בשעות:דקות:שניות. נתונים לא זמינים אינם אפס.", hebrew),
        Text(@"System data may arrive late. Current overall recording does not guarantee complete reporting "
             @"from every app.",
             @"נתוני המערכת עשויים להגיע באיחור. רישום כללי עדכני אינו מבטיח שכל אפליקציה דיווחה הכול.",
             hebrew),
        Text(@"The battery percentage in the interface is a relative share of recorded consumption, not "
             @"percentage points of battery lost.",
             @"אחוז הסוללה בממשק הוא חלק יחסי מהצריכה שנרשמה, ולא מספר נקודות האחוז שהסוללה איבדה.", hebrew),
        Text(@"CPU time refers to the current process instance and is not converted to battery consumption. "
             @"Background, audio and screen times must not be added automatically.",
             @"זמן CPU מתייחס למופע התהליך הנוכחי ואינו מומר לצריכת סוללה. אין לחבר אוטומטית זמני רקע, שמע "
             @"ומסך.",
             hebrew),
        Text(@"This report contains aggregate data only, with no app or process names, process IDs, paths or "
             @"absolute dates.",
             @"הדוח מכיל נתונים כלליים בלבד, ללא שמות אפליקציות ותהליכים, מזהי תהליכים, נתיבים או מועדים "
             @"מוחלטים.",
             hebrew)
    ] componentsJoinedByString:@"\n"];
}

NSString *IEBReadableDiagnosticReport(NSDictionary *model, NSDictionary *snapshot) {
    return IEBReadableDiagnosticReportInLanguage(model, snapshot,
                                                 NSBundle.mainBundle.preferredLocalizations.firstObject);
}
