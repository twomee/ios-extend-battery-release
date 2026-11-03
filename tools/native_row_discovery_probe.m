// Synthetic native row metadata/factory comparison; no user battery history is read.
#import "../Sources/Presentation/IEBNativeBatteryCells.h"
#import "../Sources/Presentation/IEBNativeChartController.h"
#import <dlfcn.h>
#import <objc/message.h>
@interface IEBRowMetadataProbe : NSObject
@property(nonatomic, strong) id specifier;
@property(nonatomic) NSUInteger factoryCalls;
- (id)specifierAtIndexPath:(NSIndexPath *)path;
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path;
@end
@implementation IEBRowMetadataProbe
- (id)specifierAtIndexPath:(NSIndexPath *)path {
    (void)path;
    return self.specifier;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)table;
    (void)path;
    self.factoryCalls++;
    UITableViewCell *cell = [[NSClassFromString(@"PLBatteryUIGraphViewTableCell") alloc] initWithStyle:0
                                                                                       reuseIdentifier:nil];
    ((void (*)(id, SEL, id))objc_msgSend)(cell, sel_registerName("refreshCellContentsWithSpecifier:"),
                                          self.specifier);
    return cell;
}
@end
int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PreferenceBundles/BatteryUsageUI.bundle/BatteryUsageUI", RTLD_NOW))
            return 20;
        IEBNativeChartController *host = [[IEBNativeChartController alloc] initWithSelection:nil];
        [host loadViewIfNeeded];
        UIViewController *shared = [host valueForKey:@"chart"];
        id specifier = [NSClassFromString(@"PSSpecifier") new];
        SEL setProperty = sel_registerName("setProperty:forKey:");
        NSString *__unsafe_unretained *key =
            (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, "PSCellClassKey");
        if (!key || !*key)
            return 21;
        Class graphClass = NSClassFromString(@"PLBatteryUIGraphViewTableCell");
        ((void (*)(id, SEL, id, id))objc_msgSend)(specifier, setProperty, shared,
                                                  @"PLBatteryUIGraphViewControllerKey");
        ((void (*)(id, SEL, id, id))objc_msgSend)(specifier, setProperty, graphClass, *key);
        IEBRowMetadataProbe *source = [IEBRowMetadataProbe new];
        source.specifier = specifier;
        NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
        UITableViewCell *visible = [source tableView:nil cellForRowAtIndexPath:path];
        if (IEBOriginalChartController(visible) != shared) {
            puts("synthetic_specifier_rejected=1");
            return 22;
        }
        @autoreleasepool {
            (void)[source tableView:nil cellForRowAtIndexPath:path];
        }
        ((void (*)(id, SEL, id))objc_msgSend)(visible, sel_registerName("refreshCellContentsWithSpecifier:"),
                                              specifier);
        BOOL orphaned = ![shared.view isDescendantOfView:visible];
        [visible.contentView addSubview:shared.view];
        NSUInteger before = source.factoryCalls;
        Class discovered = IEBNativeCellClassAtPath(source, path);
        BOOL preserved = discovered == graphClass && [shared.view isDescendantOfView:visible];
        printf("factory_orphans_graph=%d metadata_preserves_graph=%d metadata_factory_calls=%lu\n", orphaned,
               preserved, (unsigned long)(source.factoryCalls - before));
        return orphaned && preserved && source.factoryCalls == before ? 0 : 23;
    }
}
