#import "../tools/IEBCompatibilityEvidence.h"
#include <stdio.h>
#include <stdlib.h>
static NSUInteger invoked;
@interface IEBMetadataBase : NSObject {
  @public
    id _sample;
}
- (void)metadataEvent:(id)value;
@end
@implementation IEBMetadataBase
- (void)metadataEvent:(id)value {
    (void)value;
    invoked++;
    @throw [NSException exceptionWithName:@"Invoked" reason:nil userInfo:nil];
}
@end
@interface IEBMetadataChild : IEBMetadataBase
@end
@implementation IEBMetadataChild
@end
@interface IEBMetadataBase (Clock)
+ (id)metadataClock;
@end
@implementation IEBMetadataBase (Clock)
+ (id)metadataClock {
    invoked++;
    @throw [NSException exceptionWithName:@"Invoked" reason:nil userInfo:nil];
}
@end
static NSDictionary *Row(NSString *name, BOOL cls, BOOL member, BOOL matches) {
    return @{
        @"id" : name,
        @"class_present" : @(cls),
        @"member_present" : @(member),
        @"matches_expected" : @(matches)
    };
}
static void Check(id rows, NSUInteger count, BOOL images, NSString *expected) {
    NSDictionary *r = IEBCompatibilitySummary(rows, count, images);
    if (![r[@"status"] isEqual:expected] || r[@"supported"] != nil) {
        fprintf(stderr, "FAIL expected %s without a support claim: %s\n", expected.UTF8String,
                r.description.UTF8String);
        exit(1);
    }
}
int main(void) {
    @autoreleasepool {
        NSDictionary *inherited = IEBInspectCompatibilityMember(
            @[ @"method", @"IEBMetadataChild", @"metadataEvent:", @"v24@0:8@16" ]);
        NSDictionary *category = IEBInspectCompatibilityMember(
            @[ @"class_method", @"IEBMetadataBase", @"metadataClock", @"@16@0:8" ]);
        if (![inherited[@"matches_expected"] boolValue] ||
            ![inherited[@"declared_by"] isEqual:@"IEBMetadataBase"] ||
            ![category[@"matches_expected"] boolValue] || invoked) {
            fputs("FAIL inherited/category metadata must resolve without invoking methods\n", stderr);
            return 1;
        }
        Check(@[ IEBInspectCompatibilityMember(@[ @"ivar", @"IEBMetadataChild", @"_sample", @"present" ]) ],
              1, YES, @"metadata_match_only");
        Check(@[ IEBInspectCompatibilityMember(@[ @"method", @"IEBMetadataChild", @"missing", @"v16@0:8" ]) ],
              1, YES, @"unavailable");
        Check(@[ IEBInspectCompatibilityMember(
                  @[ @"method", @"NoSuchIEBMetadataClass", @"missing", @"v16@0:8" ]) ],
              1, YES, @"unavailable");
        Check(@[ IEBInspectCompatibilityMember(
                  @[ @"method", @"IEBMetadataChild", @"metadataEvent:", @"v16@0:8" ]) ],
              1, YES, @"abi_mismatch");
        NSDictionary *a = Row(@"inherited", YES, YES, YES), *b = Row(@"category", YES, YES, YES);
        Check(@[ a, b ], 2, YES, @"metadata_match_only");
        Check(@[ a, b ], 2, NO, @"unavailable");
        Check(@[ a ], 2, YES, @"incomplete");
        Check(@[ Row(@"missingClass", NO, NO, NO) ], 1, YES, @"unavailable");
        Check(@[ Row(@"missingSelector", YES, NO, NO) ], 1, YES, @"unavailable");
        Check(@[ Row(@"wrongABI", YES, YES, NO) ], 1, YES, @"abi_mismatch");
        Check(@[ a, a ], 2, YES, @"invalid");
        Check(@[ a, b ], 1, YES, @"invalid");
        Check(@[], 0, YES, @"invalid");
        Check(nil, 1, YES, @"invalid");
        Check(@{}, 1, YES, @"invalid");
        Check(@[ @"not a record" ], 1, YES, @"invalid");
        Check(@[ @{
                  @"id" : @"malformed",
                  @"class_present" : @"true",
                  @"member_present" : @YES,
                  @"matches_expected" : @YES
              } ],
              1, YES, @"invalid");
        Check(@[ @{
                  @"id" : @"numeric",
                  @"class_present" : @1,
                  @"member_present" : @YES,
                  @"matches_expected" : @YES
              } ],
              1, YES, @"invalid");
        Check(@[ Row(@"contradictory", NO, NO, YES) ], 1, YES, @"invalid");
        Check(@[ Row(@"contradictory", NO, YES, NO) ], 1, YES, @"invalid");
        NSDictionary *r = IEBCompatibilitySummary(@[ a, Row(@"bad", YES, YES, NO) ], 2, YES);
        if (![r[@"matched"] isEqual:@1] || ![r[@"mismatched"] isEqual:@1])
            return 1;
        puts("PASS metadata evidence preserves missing/mismatch/invalid states and never certifies OS "
             "support");
    }
    return 0;
}
