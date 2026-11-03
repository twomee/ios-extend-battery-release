#import "IEBDiagnosticReport.h"
#import "../Localization/IEBLocalization.h"
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
        @"tweak_version" : @"0.2.24",
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
static NSString *ReportDuration(id value, NSString *language) {
    id checked = Seconds(value);
    if (checked == NSNull.null)
        return IEBLocalizedInLanguage(@"UNAVAILABLE", @"Unavailable", language);
    NSInteger seconds = (NSInteger)round([checked doubleValue]);
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)(seconds / 3600), (long)(seconds / 60 % 60),
                                      (long)(seconds % 60)];
}
static NSString *Count(id value, NSString *language) {
    return [value isKindOfClass:NSNumber.class]
               ? [value description]
               : IEBLocalizedInLanguage(@"UNAVAILABLE", @"Unavailable", language);
}
NSString *IEBReadableDiagnosticReportInLanguage(NSDictionary *model, NSDictionary *snapshot,
                                                NSString *language) {
    NSDictionary *report = Summary(model, snapshot), *quality = report[@"quality"],
                 *reader = report[@"process_reader"];
    NSString *state =
        [quality[@"state"] isEqual:@"recorded"]
            ? IEBLocalizedInLanguage(
                  @"OVERALL_RECORDING_REACHED_THE_END_OF_THE_RANGE_PER_APP_COVERAGE_IS_NOT_GUAR",
                  @"Overall recording reached the end of the range; per-app coverage is not guaranteed",
                  language)
        : [quality[@"state"] isEqual:@"partial"]
            ? IEBLocalizedInLanguage(@"PARTIAL_DATA_TOTALS_MAY_CHANGE", @"Partial data; totals may change",
                                     language)
            : IEBLocalizedInLanguage(@"DATA_IS_UNAVAILABLE", @"Data is unavailable", language);
    NSString *energy = [quality[@"energy_state"] isEqual:@"recorded"]
                           ? IEBLocalizedInLanguage(@"ENERGY_RECORDS_SPAN_THE_RANGE",
                                                    @"Energy records span the range", language)
                       : [quality[@"energy_state"] isEqual:@"partial"]
                           ? IEBLocalizedInLanguage(@"PARTIAL_RECORDING_OR_UNKNOWN_COVERAGE",
                                                    @"Partial recording or unknown coverage", language)
                           : IEBLocalizedInLanguage(@"UNAVAILABLE", @"Unavailable", language);
    BOOL root = [reader[@"provider"] isEqual:@"root"];
    NSString *readerState = [reader[@"state"] isEqual:@"available"]
                                ? IEBLocalizedInLanguage(@"AVAILABLE", @"Available", language)
                            : [reader[@"state"] isEqual:@"partial"]
                                ? IEBLocalizedInLanguage(@"PARTIAL", @"Partial", language)
                                : IEBLocalizedInLanguage(@"UNAVAILABLE_2", @"Unavailable", language);
    NSString *reason =
        root ? IEBLocalizedInLanguage(@"RECEIVED_A_RESPONSE_FROM_THE_ROOT_READER",
                                      @"Received a response from the root reader", language)
        : [reader[@"reason"] isEqual:@"caller-denied"]
            ? IEBLocalizedInLanguage(@"READER_AUTHENTICATION_WAS_DENIED", @"Reader authentication was denied",
                                     language)
        : [reader[@"reason"] isEqual:@"service-timeout"]
            ? IEBLocalizedInLanguage(@"ROOT_SERVICE_TIMED_OUT", @"Root service timed out", language)
            : IEBLocalizedInLanguage(@"ROOT_SERVICE_IS_UNAVAILABLE_OR_ITS_RESPONSE_IS_INVALID",
                                     @"Root service is unavailable or its response is invalid", language);
    return [@[
        IEBLocalizedInLanguage(@"BATTERY_DIAGNOSTIC_REPORT_SINCE_UNPLUGGED",
                               @"Battery diagnostic report — Since Unplugged", language),
        [IEBLocalizedInLanguage(@"TWEAK_VERSION", @"Tweak version: ", language)
            stringByAppendingString:report[@"tweak_version"]],
        @"",
        [IEBLocalizedInLanguage(@"DATA_STATUS", @"Data status: ", language) stringByAppendingString:state],
        [IEBLocalizedInLanguage(@"RANGE_DURATION", @"Range duration: ", language)
            stringByAppendingString:ReportDuration(quality[@"range_seconds"], language)],
        [IEBLocalizedInLanguage(@"SCREEN_ON_2", @"Screen on: ", language)
            stringByAppendingString:ReportDuration(report[@"screen_on_seconds"], language)],
        [IEBLocalizedInLanguage(@"SCREEN_OFF_USAGE_2", @"Screen off usage: ", language)
            stringByAppendingString:ReportDuration(report[@"screen_off_seconds"], language)],
        [NSString stringWithFormat:IEBLocalizedInLanguage(
                                       @"ACTIVITY_RECORDED_UP_TO_FROM_THE_START_OF_THE_RANGE",
                                       @"Activity recorded up to %@ from the start of the range", language),
                                   ReportDuration(quality[@"activity_recorded_seconds"], language)],
        [IEBLocalizedInLanguage(@"TIME_AWAITING_ACTIVITY_RECORDING",
                                @"Time awaiting activity recording: ", language)
            stringByAppendingString:ReportDuration(quality[@"pending_seconds"], language)],
        [IEBLocalizedInLanguage(@"ENERGY_DATA", @"Energy data: ", language) stringByAppendingString:energy],
        [IEBLocalizedInLanguage(@"BATTERY_LEVEL_RECORDS", @"Battery level records: ", language)
            stringByAppendingString:[quality[@"levels_available"] boolValue]
                                        ? IEBLocalizedInLanguage(@"AVAILABLE_2", @"Available", language)
                                        : IEBLocalizedInLanguage(@"UNAVAILABLE_3", @"Unavailable", language)],
        [IEBLocalizedInLanguage(@"APP_SOURCE_COUNT", @"App source count: ", language)
            stringByAppendingString:Count(report[@"app_source_count"], language)],
        [quality[@"recovered_cycle"] boolValue]
            ? IEBLocalizedInLanguage(
                  @"THE_CYCLE_WAS_RECOVERED_UP_TO_THE_LAST_SAVE_THE_TIME_AFTER_IT_IS_UNKNOWN",
                  @"The cycle was recovered up to the last save; the time after it is unknown.", language)
            : @"",
        @"",
        IEBLocalizedInLanguage(@"PROCESS_READING", @"Process reading", language),
        root ? IEBLocalizedInLanguage(@"DATA_PROVIDER_ROOT_ACCESS", @"Data provider: Root access", language)
             : IEBLocalizedInLanguage(@"DATA_PROVIDER_LIMITED_PERMISSIONS",
                                      @"Data provider: Limited permissions", language),
        [IEBLocalizedInLanguage(@"PROCESS_SNAPSHOT", @"Process snapshot: ", language)
            stringByAppendingString:readerState],
        [IEBLocalizedInLanguage(@"READABLE_PROCESSES", @"Readable processes: ", language)
            stringByAppendingString:Count(reader[@"readable"], language)],
        [IEBLocalizedInLanguage(@"PERMISSION_DENIED", @"Permission denied: ", language)
            stringByAppendingString:Count(reader[@"denied"], language)],
        [IEBLocalizedInLanguage(@"VANISHED_DURING_SAMPLING", @"Vanished during sampling: ", language)
            stringByAppendingString:Count(reader[@"vanished"], language)],
        [IEBLocalizedInLanguage(@"UNNAMED_PROCESSES", @"Unnamed processes: ", language)
            stringByAppendingString:Count(reader[@"unnamed"], language)],
        [IEBLocalizedInLanguage(@"LIST_TRUNCATED", @"List truncated: ", language)
            stringByAppendingString:[reader[@"truncated"] boolValue]
                                        ? IEBLocalizedInLanguage(@"YES", @"Yes", language)
                                        : IEBLocalizedInLanguage(@"NO", @"No", language)],
        [IEBLocalizedInLanguage(@"ROOT_SERVICE_STATUS", @"Root service status: ", language)
            stringByAppendingString:reason],
        @"",
        IEBLocalizedInLanguage(@"HOW_TO_INTERPRET_THE_DATA", @"How to interpret the data", language),
        IEBLocalizedInLanguage(@"ALL_TIMES_USE_HOURS_MINUTES_SECONDS_UNAVAILABLE_DATA_IS_NOT_ZERO",
                               @"All times use hours:minutes:seconds. Unavailable data is not zero.",
                               language),
        IEBLocalizedInLanguage(@"SYSTEM_DATA_MAY_ARRIVE_LATE_CURRENT_OVERALL_RECORDING_DOES_NOT_GUARANTEE_CO",
                               @"System data may arrive late. Current overall recording does not guarantee "
                               @"complete reporting from every app.",
                               language),
        IEBLocalizedInLanguage(@"THE_BATTERY_PERCENTAGE_IN_THE_INTERFACE_IS_A_RELATIVE_SHARE_OF_RECORDED_CON",
                               @"The battery percentage in the interface is a relative share of recorded "
                               @"consumption, not percentage points of battery lost.",
                               language),
        IEBLocalizedInLanguage(
            @"CPU_TIME_REFERS_TO_THE_CURRENT_PROCESS_INSTANCE_AND_IS_NOT_CONVERTED_TO_BAT",
            @"CPU time refers to the current process instance and is not converted to battery consumption. "
            @"Background, audio and screen times must not be added automatically.",
            language),
        IEBLocalizedInLanguage(@"THIS_REPORT_CONTAINS_AGGREGATE_DATA_ONLY_WITH_NO_APP_OR_PROCESS_NAMES_PROCE",
                               @"This report contains aggregate data only, with no app or process names, "
                               @"process IDs, paths or absolute dates.",
                               language)
    ] componentsJoinedByString:@"\n"];
}

NSString *IEBReadableDiagnosticReport(NSDictionary *model, NSDictionary *snapshot) {
    return IEBReadableDiagnosticReportInLanguage(model, snapshot, IEBCurrentLanguage());
}
