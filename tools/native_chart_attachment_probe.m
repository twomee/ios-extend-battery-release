// Synthetic view ownership only: no battery history, app identities or Settings navigation.
#import "../Sources/Presentation/IEBNativeBatteryCells.h"
#import "../Sources/Presentation/IEBNativeChartController.h"
#import <dlfcn.h>
#import <objc/runtime.h>
int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PreferenceBundles/BatteryUsageUI.bundle/BatteryUsageUI", RTLD_NOW))
            return 20;
        Class cellClass = NSClassFromString(@"PLBatteryUIGraphViewTableCell");
        Ivar controllerIvar = class_getInstanceVariable(cellClass, "_controller");
        if (!cellClass || !controllerIvar)
            return 21;
        IEBNativeChartController *host = [[IEBNativeChartController alloc] initWithSelection:nil];
        [host loadViewIfNeeded];
        UIViewController *shared = [host valueForKey:@"chart"];
        UITableViewCell *first = [[cellClass alloc] initWithStyle:0 reuseIdentifier:nil];
        object_setIvar(first, controllerIvar, shared);
        first.frame = CGRectMake(0, 0, 390, 330);
        [first.contentView addSubview:shared.view];
        shared.view.frame = CGRectMake(0, 0, 390, 330);
        UIView *replacement = [UIView new];
        BOOL attached = IEBAttachNativeChart(first, replacement);
        UITableViewCell *second = [[cellClass alloc] initWithStyle:0 reuseIdentifier:nil];
        object_setIvar(second, controllerIvar, shared);
        second.frame = CGRectMake(0, 0, 390, 330);
        [second.contentView addSubview:shared.view];
        attached &= IEBAttachNativeChart(second, replacement);
        IEBRestoreNativeChart(first);
        BOOL active = shared.view.hidden && [replacement isDescendantOfView:second];
        IEBRestoreNativeChart(second);
        BOOL restored = !shared.view.hidden && replacement.superview == nil;
        printf("attached=%d active_after_old_cell_cleanup=%d native_restored=%d\n", attached, active,
               restored);
        return attached && active && restored ? 0 : 22;
    }
}
