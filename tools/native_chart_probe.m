// Synthetic-only native ABI/lifecycle check. Does not query battery history or open Settings.
#import "../Sources/Presentation/IEBNativeChartController.h"
#import <dlfcn.h>
int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PreferenceBundles/BatteryUsageUI.bundle/BatteryUsageUI", RTLD_NOW))
            return 20;
        __block NSUInteger callbacks = 0;
        IEBNativeChartController *host =
            [[IEBNativeChartController alloc] initWithSelection:^(NSDictionary *range) {
                (void)range;
                callbacks++;
            }];
        host.presentation = @{
            @"top_margin" : @8,
            @"bottom_margin" : @12,
            @"background" : UIColor.secondarySystemGroupedBackgroundColor
        };
        NSDictionary *model = @{
            @"range" : @{@"start" : @1699996315, @"end" : @1700000000},
            @"levels" :
                @[ @{@"time" : @1699996315,
                     @"level" : @80},
                   @{@"time" : @1699999900,
                     @"level" : @75} ],
            @"activity_buckets" : @[
                @{@"start" : @1699996315,
                  @"end" : @1700000000,
                  @"ScreenOn" : @3000,
                  @"ScreenOff" : @50}
            ]
        };
        BOOL configured = [host configureOverview:model selectedStart:1699999200 selectedEnd:1700000000];
        [host loadViewIfNeeded];
        CGFloat height = [IEBNativeChartController heightForTraits:host.traitCollection];
        printf("native_abi=%d synthetic_dataset=%d children=%lu unexpected_callbacks=%lu height=%.1f\n",
               [IEBNativeChartController isSupported], configured,
               (unsigned long)host.childViewControllers.count, (unsigned long)callbacks, (double)height);
        return host && configured && host.childViewControllers.count == 1 && callbacks == 0 ? 0 : 21;
    }
}
