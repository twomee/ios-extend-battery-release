#import "../Sources/Compatibility/IEBPlatformSupport.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import "../Sources/Presentation/IEBStatisticsController.h"
#import "../Sources/Presentation/IEBSettingsPanel.h"
#import "../Sources/Presentation/IEBNativeChartController.h"
#import "../Sources/Presentation/IEBNativeBatteryCells.h"
#import "../Sources/Statistics/IEBStatisticsModel.h"
@interface PSSpecifier : NSObject
- (NSArray *)values;
- (NSDictionary *)titleDictionary;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end
@interface BatteryUIController : UIViewController
- (void)setBatteryUIQueryRange:(id)value specifier:(id)specifier;
@end
@interface PLBatteryUISegmentCell : UITableViewCell
@end
static UISegmentedControl *FindSegment(UIView *view) {
    if([view isKindOfClass:UISegmentedControl.class]) return (UISegmentedControl *)view;
    for(UIView *sub in view.subviews) { UISegmentedControl *hit=FindSegment(sub); if(hit) return hit; }
    return nil;
}
static UISegmentedControl *FindRange(UIView *view) {
    if([view isKindOfClass:NSClassFromString(@"PLBatteryUISegmentCell")]) return FindSegment(view);
    for(UIView *sub in view.subviews) { UISegmentedControl *hit=FindRange(sub); if(hit) return hit; }
    return nil;
}
static UIViewController *Owner(UIView *view) {
    UIResponder *responder=view;
    Class cls=NSClassFromString(@"BatteryUIController");
    while(responder) { if([responder isKindOfClass:cls]) return (UIViewController *)responder; responder=responder.nextResponder; }
    return nil;
}
static void RememberGraphCell(UITableViewCell *cell) {
    Ivar ivar=class_getInstanceVariable(cell.class,"_controller");
    if(!ivar || !ivar_getTypeEncoding(ivar) || ivar_getTypeEncoding(ivar)[0]!='@') return;
    id controller=object_getIvar(cell,ivar);
    if([controller isKindOfClass:UIViewController.class]) IEBRememberNativeChartLayout(cell,controller);
}
%group IEBSettingsHooks
%hook IEBSystemChart
- (void)setMarginWithTop:(double)top bottom:(double)bottom {
    %orig;
    IEBRememberNativeChartMargins((UIViewController *)self,top,bottom);
}
- (void)setContainerBackgroundColor:(id)color {
    %orig;
    IEBRememberNativeChartBackground((UIViewController *)self,color);
}
- (void)setDataset:(id)dataset endOfDay:(id)endOfDay {
    %orig;
    IEBRememberNativeChartAnchor((UIViewController *)self,endOfDay);
}
%end
%hook PLBatteryUIGraphViewTableCell
- (void)layoutSubviews {
    %orig;
    RememberGraphCell((UITableViewCell *)self);
    IEBLayoutNativeChart((UITableViewCell *)self);
}
%end
%hook PLBatteryUITimeUsageCell
- (void)handleGesture:(id)gesture {
    if(!IEBNativeTimeUsageIsActive((UITableViewCell *)self)) { %orig; }
}
- (void)refreshCellContentsWithSpecifier:(id)specifier {
    %orig;
    IEBRefreshNativeTimeUsage((UITableViewCell *)self);
}
%end
%hook BatteryUIController
- (void)setBatteryUIQueryRange:(id)value specifier:(id)specifier {
    id selected=[value isKindOfClass:NSClassFromString(@"PSSpecifier")] ? specifier:value;
    if([selected respondsToSelector:@selector(integerValue)]) IEBRememberSettingsRange(self,[selected integerValue]);
    if([selected respondsToSelector:@selector(integerValue)] && [selected integerValue]==2) {
        if (!IEBHasSettingsPanel(self)) {
            IEBStatisticsController *statistics=[[IEBStatisticsController alloc] initWithLoader:^NSDictionary *(double start,double end,NSError **error) { return IEBLoadStatistics(@"/var/mobile/Library/IEBNativeCapture",nil,start,end,error); }];
            __weak BatteryUIController *weakOwner=self;
            BOOL reversed=[value isKindOfClass:NSClassFromString(@"PSSpecifier")];
            __weak id weakSpecifier=reversed ? value : specifier;
            BOOL shown=IEBShowSettingsPanel(self,FindRange(self.view),statistics,^(NSInteger range){
                BatteryUIController *owner=weakOwner;
                if(!owner) return;
                IEBSelectNativeRange(owner,FindRange(owner.view),weakSpecifier,reversed,range);
            });
            if (!shown) IEBSelectNativeRange(self,FindRange(self.view),weakSpecifier,reversed,0);
        }
        return;
    }
    IEBDismissSettingsPanel(self);
    %orig;
    IEBSyncSettingsRange(self,FindRange(self.view));
}
- (void)viewDidLayoutSubviews {
    %orig;
    UISegmentedControl *control=FindRange(self.view);
    IEBRebindSettingsPanel(self,control);
    IEBSyncSettingsRange(self,control);
}
%end
%hook PLBatteryUISegmentCell
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    NSArray *values=[specifier values]; NSDictionary *titles=[specifier titleDictionary];
    if(values.count==2) {
        NSMutableArray *labels=[NSMutableArray new];
        for(id value in values) [labels addObject:[titles[value] ?: titles[[value description]] ?: [value description] description]];
        [labels addObject:IEBLocalized(@"SINCE_UNPLUGGED", @"Since Unplugged")];
        [specifier setValues:[values arrayByAddingObject:@2] titles:labels];
    }
    %orig;
    UISegmentedControl *control=FindSegment(self);
    if(control.numberOfSegments==3) {
        [control setTitleTextAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
        UIViewController *owner=Owner(self);
        if(owner) { IEBSyncSettingsRange(owner,control); if(IEBHasSettingsPanel(owner)) IEBRebindSettingsPanel(owner,control); }
    }
}
%end
%end
static BOOL installed;
static void Install(void) {
    if(installed) return;
    NSDictionary *version=[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    if(!IEBPlatformIsSupported(version[@"ProductVersion"], version[@"ProductBuildVersion"])) return;
    Method action=class_getInstanceMethod(NSClassFromString(@"BatteryUIController"),sel_registerName("setBatteryUIQueryRange:specifier:"));
    Method refresh=class_getInstanceMethod(NSClassFromString(@"PLBatteryUISegmentCell"),sel_registerName("refreshCellContentsWithSpecifier:"));
    Method setValues=class_getInstanceMethod(NSClassFromString(@"PSSpecifier"),sel_registerName("setValues:titles:"));
    if(!action || !refresh || !setValues || strcmp(method_getTypeEncoding(action),"v32@0:8@16@24") || strcmp(method_getTypeEncoding(refresh),"v24@0:8@16") || strcmp(method_getTypeEncoding(setValues),"v32@0:8@16@24")) return;
    Class chart=NSClassFromString(@"_TtC14BatteryUsageUI24PLBUIChartViewController");
    Method chartDataset=class_getInstanceMethod(chart,sel_registerName("setDataset:endOfDay:"));
    Method graphLayout=class_getInstanceMethod(NSClassFromString(@"PLBatteryUIGraphViewTableCell"),@selector(layoutSubviews));
    Method margins=class_getInstanceMethod(chart,sel_registerName("setMarginWithTop:bottom:"));
    Method background=class_getInstanceMethod(chart,sel_registerName("setContainerBackgroundColor:"));
    Method timesRefresh=class_getInstanceMethod(NSClassFromString(@"PLBatteryUITimeUsageCell"),sel_registerName("refreshCellContentsWithSpecifier:"));
    if(!margins || strcmp(method_getTypeEncoding(margins),"v32@0:8d16d24") || !background || strcmp(method_getTypeEncoding(background),"v24@0:8@16") || !timesRefresh || strcmp(method_getTypeEncoding(timesRefresh),"v24@0:8@16")) return;
    Method timeGesture=class_getInstanceMethod(NSClassFromString(@"PLBatteryUITimeUsageCell"),sel_registerName("handleGesture:"));
    if(!timeGesture || strcmp(method_getTypeEncoding(timeGesture),"v24@0:8@16")) return;
    if(!IEBNativeTimeUsageSupported()) return;
    if(!chartDataset || strcmp(method_getTypeEncoding(chartDataset),"v32@0:8@16@24") || !graphLayout || strcmp(method_getTypeEncoding(graphLayout),"v16@0:8")) return;
    %init(IEBSettingsHooks,IEBSystemChart=chart); installed=YES;
}
static void Image(const struct mach_header *header,intptr_t slide) {
    (void)slide; Dl_info info;
    if(dladdr(header,&info) && info.dli_fname && strstr(info.dli_fname,"BatteryUsageUI")) dispatch_async(dispatch_get_main_queue(),^{ Install(); });
}
%ctor { @autoreleasepool { _dyld_register_func_for_add_image(Image); Install(); } }
