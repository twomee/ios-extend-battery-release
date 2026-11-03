#import "../Sources/Statistics/IEBEnergyIntervals.h"
#import <math.h>
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Energy FAIL %d: %s\n", __LINE__, #c);                                           \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDictionary *Row(NSInteger ID, double timestamp, double startMS, double endMS, double energy,
                         double correction, double ratio) {
    return @{
        @"ID" : @(ID),
        @"timestamp" : @(timestamp),
        @"StartOffset" : @(startMS),
        @"EndOffset" : @(endMS),
        @"Energy" : @(energy),
        @"CorrectionEnergy" : @(correction),
        @"TerminationRatio" : @(ratio)
    };
}
int main(void) {
    @autoreleasepool {
        NSDictionary *r = Row(1, 110, -10000, 0, 100, 20, 50); // [100,110), final60
        NSDictionary *full = IEBEnergyForWindow(@[ r ], 100, 110, NULL);
        REQUIRE([full[@"estimated_native_units"] doubleValue] == 60);
        REQUIRE([full[@"lower_native_units"] doubleValue] == 60);
        REQUIRE([full[@"upper_native_units"] doubleValue] == 60);
        REQUIRE([full[@"allocation_exact"] isEqual:@YES]);
        NSDictionary *partial = IEBEnergyForWindow(@[ r ], 105, 110, NULL);
        REQUIRE([partial[@"estimated_native_units"] doubleValue] == 30);
        REQUIRE([partial[@"lower_native_units"] doubleValue] == 0);
        REQUIRE([partial[@"upper_native_units"] doubleValue] == 60);
        REQUIRE([partial[@"boundary_interval_count"] isEqual:@1]);
        REQUIRE([partial[@"allocation_exact"] isEqual:@NO]);
        NSDictionary *left = IEBEnergyForWindow(@[ r ], 100, 105, NULL);
        REQUIRE([left[@"estimated_native_units"] doubleValue] +
                    [partial[@"estimated_native_units"] doubleValue] ==
                60);
        REQUIRE([IEBEnergyForWindow(@[ r ], 110, 120, NULL)[@"overlapping_interval_count"] isEqual:@0]);
        REQUIRE([IEBEnergyForWindow(@[ Row(2, 110, -10000, 0, 100, 0, 0) ], 100, 110,
                                    NULL)[@"estimated_native_units"] isEqual:@0]);
        REQUIRE([IEBEnergyForWindow(@[ Row(3, 110, -10000, 0, 1, 0, 50) ], 100, 110,
                                    NULL)[@"estimated_native_units"] isEqual:@1]);
        REQUIRE([IEBEnergyForWindow(@[ Row(4, 110, -10000, 0, 100, -20, 100) ], 100, 110,
                                    NULL)[@"estimated_native_units"] isEqual:@80]);
        REQUIRE(IEBEnergyForWindow(@[ Row(5, 110, 0, 0, 0, 0, 100) ], 100, 120, NULL) != nil);
        REQUIRE(IEBEnergyForWindow(@[ Row(6, 110, 0, 0, 10, 0, 100) ], 100, 120, NULL) == nil);
        NSError *error = nil;
        REQUIRE(IEBEnergyForWindow(@[ r, r ], 100, 110, &error) == nil && error);
        REQUIRE(IEBEnergyForWindow(@[ Row(7, 110, 0, -1, 10, 0, 100) ], 100, 120, NULL) == nil);
        REQUIRE(IEBEnergyForWindow(@[ Row(8, 110, -10000, 0, 10, -20, 100) ], 100, 120, NULL) == nil);
        REQUIRE(IEBEnergyForWindow(@[ Row(9, 110, -10000, 0, 10, 0, 101) ], 100, 120, NULL) == nil);
        REQUIRE(IEBEnergyForWindow(@[ Row(10, NAN, -10000, 0, 10, 0, 100) ], 100, 120, NULL) == nil);
        REQUIRE(IEBEnergyForWindow(@[ @{} ], 100, 110, NULL) == nil);
        REQUIRE(IEBEnergyForWindow(@[], 110, 100, NULL) == nil);
        REQUIRE(IEBEnergyForWindow(@[], 100, 110, NULL) != nil);
        REQUIRE([NSJSONSerialization isValidJSONObject:partial]);
        puts("PASS energy intervals, corrections, termination, allocation bounds");
    }
    return 0;
}
