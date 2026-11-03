#import "../Sources/Compatibility/IEBCollectorBootstrap.h"
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
static void Check(BOOL value, const char *message) {
    if (!value) {
        fprintf(stderr, "FAIL %s\n", message);
        exit(1);
    }
}
int main(void) {
    @autoreleasepool {
        NSArray *orders = @[
            @[ @0, @1, @2 ], @[ @0, @2, @1 ], @[ @1, @0, @2 ], @[ @1, @2, @0 ], @[ @2, @0, @1 ],
            @[ @2, @1, @0 ]
        ];
        for (NSArray *order in orders) {
            __block unsigned ready = 0;
            __block NSUInteger starts = 0;
            IEBCollectorBootstrap *boot = [[IEBCollectorBootstrap alloc]
                initWithReadiness:^{
                    return (BOOL)(ready == 7);
                }
                start:^{
                    starts++;
                }];
            [boot attempt];
            Check(starts == 0, "missing interfaces must wait");
            for (NSNumber *part in order) {
                ready |= 1U << part.unsignedIntValue;
                [boot attempt];
                [boot attempt];
                Check(starts == (ready == 7 ? 1U : 0U),
                      "late interfaces must retry, then start exactly once");
            }
            [boot attempt];
            Check(starts == 1, "repeated images must not reinstall hooks");
        }
        for (NSString *name in @[ @"PowerlogCore", @"PowerlogLiteOperators", @"PowerlogHelperdOperators" ]) {
            NSString *path =
                [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@", name, name];
            Check(IEBIsCollectorFrameworkImage(path.UTF8String),
                  "all collector dependencies must trigger retry");
        }
        Check(!IEBIsCollectorFrameworkImage(NULL), "null image");
        Check(!IEBIsCollectorFrameworkImage("/tmp/NotPowerlogCore"), "unrelated image");
        Check(!IEBIsCollectorFrameworkImage("/tmp/PowerlogHelperdOperatorsExtra"),
              "similar name must not match");
        __block NSUInteger reentrantStarts = 0;
        __weak IEBCollectorBootstrap *weakBoot;
        IEBCollectorBootstrap *reentrant = [[IEBCollectorBootstrap alloc]
            initWithReadiness:^{
                return YES;
            }
            start:^{
                reentrantStarts++;
                [weakBoot attempt];
            }];
        weakBoot = reentrant;
        [reentrant attempt];
        Check(reentrantStarts == 1, "start reentrancy must not duplicate hooks");
        __block BOOL backgroundStarted = NO;
        IEBCollectorBootstrap *background = [[IEBCollectorBootstrap alloc]
            initWithReadiness:^{
                return YES;
            }
            start:^{
                Check(NSThread.isMainThread, "startup must run on main");
                backgroundStarted = YES;
            }];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [background attempt];
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!backgroundStarted && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        Check(backgroundStarted, "background request must be marshalled to main");
        puts("PASS six synthetic dependency orders, late readiness, image filter, exactly-once/reentrant and "
             "main-thread startup");
    }
    return 0;
}
