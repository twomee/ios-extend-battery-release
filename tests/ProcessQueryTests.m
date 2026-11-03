#import "../Sources/Diagnostics/IEBProcessQuery.h"
#import <Foundation/Foundation.h>
#define C(...)                                                                                               \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Process query FAIL %d\n", __LINE__);                                            \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSArray *rows = @[
            @{
                @"pid" : @11,
                @"name" : @"Alpha",
                @"cpu_percent" : @20,
                @"cpu_seconds" : @100,
                @"energy_percent" : NSNull.null
            },
            @{
                @"pid" : @42,
                @"name" : @"beta",
                @"cpu_percent" : NSNull.null,
                @"cpu_seconds" : @20,
                @"energy_percent" : @5
            },
            @{
                @"pid" : @7,
                @"name" : @"ALPÍNE",
                @"cpu_percent" : @10,
                @"cpu_seconds" : @200,
                @"energy_percent" : @12
            },
            @{
                @"pid" : @9,
                @"name" : @"gamma",
                @"cpu_percent" : @5,
                @"cpu_seconds" : NSNull.null,
                @"energy_percent" : @0
            }
        ];
        C([[IEBQueryProcesses(rows, @"", @"cpu") valueForKey:@"pid"] isEqual:@[ @11, @7, @9, @42 ]]);
        C([[IEBQueryProcesses(rows, @"alp", @"name") valueForKey:@"pid"] isEqual:@[ @11, @7 ]]);
        C([[IEBQueryProcesses(rows, @"alpine", @"name") valueForKey:@"pid"] isEqual:@[ @7 ]]);
        C([[IEBQueryProcesses(rows, @"42", @"cpu") valueForKey:@"pid"] isEqual:@[ @42 ]]);
        C([[IEBQueryProcesses(rows, @"  ", @"energy") valueForKey:@"pid"] isEqual:@[ @7, @42, @9, @11 ]]);
        C([[IEBQueryProcesses(rows, nil, @"lifetime") valueForKey:@"pid"] isEqual:@[ @7, @11, @42, @9 ]]);
        C(IEBQueryProcesses(rows, @"missing", @"cpu").count == 0);
        C([[IEBQueryProcesses(rows, nil, @"bad") valueForKey:@"pid"] isEqual:@[ @11, @7, @9, @42 ]]);
        C([[rows valueForKey:@"pid"] isEqual:@[ @11, @42, @7, @9 ]]);
        C(IEBQueryProcesses(@[ NSNull.null, @{}, @{@"pid" : @YES} ], nil, @"name").count == 0);
        NSArray *ties = @[
            @{@"pid" : @2,
              @"name" : @"same",
              @"cpu_percent" : @10},
            @{@"pid" : @1,
              @"name" : @"same",
              @"cpu_percent" : @10}
        ];
        C([[IEBQueryProcesses(ties, nil, @"cpu") valueForKey:@"pid"] isEqual:@[ @1, @2 ]]);
        puts("PASS process name/PID search, metric sorts, unknown-last and stable immutable sampling");
        return 0;
    }
}
