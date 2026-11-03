#import "../Sources/Diagnostics/IEBProcessReaderStatus.h"
#import <Foundation/Foundation.h>
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Reader status FAIL %d\n", __LINE__);                                            \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSDictionary *root = IEBProcessReaderStatus(@{
            @"reader_provider" : @"root-service",
            @"status" : @"available",
            @"rows" : @[ @{}, @{} ],
            @"permission_denied_count" : @0,
            @"vanished_count" : @0,
            @"name_unavailable_count" : @0,
            @"enumeration_truncated" : @NO
        });
        C([root[@"provider"] isEqual:@"root"] && [root[@"readable"] isEqual:@2]);
        C([root[@"state"] isEqual:@"available"]);
        NSDictionary *limited = IEBProcessReaderStatus(@{
            @"reader_provider" : @"mobile",
            @"rows" : @[ @{} ],
            @"status" : @"partial",
            @"permission_denied_count" : @100,
            @"reader_failure" : @"caller-denied",
            @"vanished_count" : @2,
            @"name_unavailable_count" : @1,
            @"enumeration_truncated" : @YES
        });
        C([limited[@"provider"] isEqual:@"limited"] && [limited[@"denied"] isEqual:@100]);
        C([limited[@"vanished"] isEqual:@2] && [limited[@"unnamed"] isEqual:@1] &&
          [limited[@"truncated"] boolValue]);
        C([limited[@"reason"] isEqual:@"caller-denied"] && [limited[@"state"] isEqual:@"partial"]);
        C([IEBProcessReaderStatus(@{@"reader_failure" : @"/private/secret-process"})[@"reason"]
            isEqual:@"unknown"]);
        C([IEBProcessReaderStatus(nil)[@"state"] isEqual:@"unavailable"]);
        C(IEBProcessReaderStatus(nil)[@"denied"] == NSNull.null);
        puts("PASS process reader status exposes partial access without identities or raw failures");
        return 0;
    }
}
