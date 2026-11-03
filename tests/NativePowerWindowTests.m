#import "../Sources/Session/IEBNativePowerWindow.h"
#import <math.h>
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Native power FAIL %d: %s\n", __LINE__, #c);                                     \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDictionary *E(NSString *epoch, double t) {
    return @{@"kind" : @"epoch", @"epoch" : epoch, @"time" : @(t)};
}
static NSDictionary *P(NSInteger p, double t) {
    return @{@"kind" : @"power", @"power" : @(p), @"time" : @(t)};
}
static NSDictionary *G(double t) {
    return @{@"kind" : @"gap", @"time" : @(t)};
}
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSArray *events = @[ E(@"a", 100), P(1, 100), P(0, 110), P(0, 140), P(1, 300) ];
        NSDictionary *w = IEBNativePowerWindow(events, &error);
        REQUIRE(w && !error && [w[@"start"] doubleValue] == 110 && [w[@"end"] doubleValue] == 300 &&
                [w[@"power_complete"] boolValue]);
        REQUIRE([w[@"epoch"] isEqual:@"a"]);
        w = IEBNativePowerWindow(@[ E(@"a", 100), P(0, 110) ], &error);
        REQUIRE(w && !w[@"start"] && ![w[@"power_complete"] boolValue]);
        w = IEBNativePowerWindow(@[ E(@"a", 100), P(1, 101), P(0, 110), P(1, 200), P(0, 200.1), P(1, 235) ],
                                 &error);
        REQUIRE([w[@"start"] doubleValue] == 200.1 && [w[@"end"] doubleValue] == 235);
        w = IEBNativePowerWindow(@[ E(@"a", 100), P(1, 100), P(0, 110), P(0, 140), G(150), P(1, 300) ],
                                 &error);
        REQUIRE(w && [w[@"end"] doubleValue] == 140 && ![w[@"power_complete"] boolValue]);
        w = IEBNativePowerWindow(@[ E(@"a", 100), P(1, 100), P(0, 110), P(0, 140), E(@"b", 50), P(1, 60) ],
                                 &error);
        REQUIRE(w && [w[@"end"] doubleValue] == 140 && ![w[@"power_complete"] boolValue] &&
                [w[@"epoch"] isEqual:@"a"]);
        NSMutableArray *a = [events mutableCopy];
        [a addObjectsFromArray:@[ G(350), E(@"b", 50), P(1, 60) ]];
        w = IEBNativePowerWindow(a, &error);
        REQUIRE([w[@"end"] doubleValue] == 300 && [w[@"power_complete"] boolValue]);
        [a addObjectsFromArray:@[ P(0, 70), P(1, 90) ]];
        w = IEBNativePowerWindow(a, &error);
        REQUIRE([w[@"start"] doubleValue] == 70 && [w[@"end"] doubleValue] == 90 &&
                [w[@"epoch"] isEqual:@"b"]);
        REQUIRE(!IEBNativePowerWindow(@[ P(1, 100) ], &error) && error);
        REQUIRE(!IEBNativePowerWindow(@[ E(@"a", 100), P(1, 99) ], &error) && error);
        REQUIRE(!IEBNativePowerWindow(@[ E(@"a", 100), P(1, 110), P(0, 110) ], &error) && error);
        REQUIRE(!IEBNativePowerWindow(@[ E(@"a", 100), P(1, 110), P(-1, 120) ], &error) && error);
        REQUIRE(!IEBNativePowerWindow(@[ E(@"a", 100), P(1, NAN) ], &error) && error);
        REQUIRE(!IEBNativePowerWindow(@[ E(@"a", 100), E(@"a", 200) ], &error) && error);
        REQUIRE(!IEBNativePowerWindow((id) @{}, &error) && error);
        REQUIRE(IEBNativePowerWindow(@[], &error) && !error);
        puts("PASS native power windows, brief charges, gaps and epochs");
        return 0;
    }
}
