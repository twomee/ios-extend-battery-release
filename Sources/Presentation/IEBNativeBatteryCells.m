#import "IEBNativeBatteryCells.h"
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
static const void *TimesKey = &TimesKey;
static const void *OriginalTimesKey = &OriginalTimesKey;
static const void *ChartKey = &ChartKey;
static const void *ReplacementKey = &ReplacementKey;
@interface IEBChartAttachment : NSObject
@property(nonatomic, weak) UITableViewCell *cell;
@property(nonatomic, weak) UIView *replacement;
@property(nonatomic, strong) UIView *original;
@property(nonatomic) BOOL originalHidden;
@end
@implementation IEBChartAttachment
@end
static void RestoreAttachment(IEBChartAttachment *attachment) {
    if (!attachment)
        return;
    UIView *replacement = attachment.replacement;
    if (objc_getAssociatedObject(replacement, ReplacementKey) == attachment) {
        [replacement removeFromSuperview];
        attachment.original.hidden = attachment.originalHidden;
        objc_setAssociatedObject(replacement, ReplacementKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (objc_getAssociatedObject(attachment.cell, ChartKey) == attachment)
        objc_setAssociatedObject(attachment.cell, ChartKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id ObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable([object class], name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}
BOOL IEBNativeTimeUsageSupported(void) {
    Class cls = NSClassFromString(@"PLBatteryUITimeUsageCell");
    Method formatter =
        class_getInstanceMethod(cls, sel_registerName("getLoczlizedHourMinuteStringFromSeconds:"));
    return cls && formatter && strcmp(method_getTypeEncoding(formatter), "@24@0:8d16") == 0 &&
           class_getInstanceVariable(cls, "_screenOnTimeText") &&
           class_getInstanceVariable(cls, "_screenOffTimeText");
}
static NSString *TimeText(UITableViewCell *cell, id seconds) {
    if (![seconds isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)seconds) == CFBooleanGetTypeID() ||
        !isfinite([seconds doubleValue]) || [seconds doubleValue] < 0)
        return @"—";
    return ((id(*)(id, SEL, double))objc_msgSend)(
        cell, sel_registerName("getLoczlizedHourMinuteStringFromSeconds:"), [seconds doubleValue]);
}
void IEBRefreshNativeTimeUsage(UITableViewCell *cell) {
    NSArray *times = objc_getAssociatedObject(cell, TimesKey);
    if (!times)
        return;
    UILabel *on = ObjectIvar(cell, "_screenOnTimeText"), *off = ObjectIvar(cell, "_screenOffTimeText");
    if (![on isKindOfClass:UILabel.class] || ![off isKindOfClass:UILabel.class])
        return;
    on.text = TimeText(cell, times[0]);
    off.text = TimeText(cell, times[1]);
    [cell setNeedsLayout];
}
BOOL IEBApplyNativeTimeUsage(UITableViewCell *cell, id screenOn, id screenOff) {
    if (!IEBNativeTimeUsageSupported() ||
        ![cell isKindOfClass:NSClassFromString(@"PLBatteryUITimeUsageCell")])
        return NO;
    UILabel *on = ObjectIvar(cell, "_screenOnTimeText"), *off = ObjectIvar(cell, "_screenOffTimeText");
    if (![on isKindOfClass:UILabel.class] || ![off isKindOfClass:UILabel.class])
        return NO;
    if (!objc_getAssociatedObject(cell, OriginalTimesKey)) {
        objc_setAssociatedObject(cell, OriginalTimesKey, @{@"on" : on.text ?: @"", @"off" : off.text ?: @""},
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(cell, TimesKey, @[ screenOn ?: NSNull.null, screenOff ?: NSNull.null ],
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    IEBRefreshNativeTimeUsage(cell);
    return YES;
}
void IEBRestoreNativeTimeUsage(UITableViewCell *cell) {
    NSDictionary *original = objc_getAssociatedObject(cell, OriginalTimesKey);
    objc_setAssociatedObject(cell, TimesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!original)
        return;
    UILabel *on = ObjectIvar(cell, "_screenOnTimeText"), *off = ObjectIvar(cell, "_screenOffTimeText");
    if ([on isKindOfClass:UILabel.class])
        on.text = original[@"on"];
    if ([off isKindOfClass:UILabel.class])
        off.text = original[@"off"];
    objc_setAssociatedObject(cell, OriginalTimesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
UIViewController *IEBOriginalChartController(UITableViewCell *cell) {
    id controller = ObjectIvar(cell, "_controller");
    return [controller isKindOfClass:UIViewController.class] ? controller : nil;
}
BOOL IEBAttachNativeChart(UITableViewCell *cell, UIView *replacement) {
    UIViewController *controller = IEBOriginalChartController(cell);
    if (!controller || !replacement || !controller.isViewLoaded ||
        ![controller.view isDescendantOfView:cell] || controller.view == replacement)
        return NO;
    IEBChartAttachment *active = objc_getAssociatedObject(replacement, ReplacementKey);
    if (active && (active.cell != cell || active.original != controller.view)) {
        RestoreAttachment(active);
        active = nil;
    }
    IEBChartAttachment *previous = objc_getAssociatedObject(cell, ChartKey);
    if (previous && previous != active)
        RestoreAttachment(previous);
    if (!active) {
        active = [IEBChartAttachment new];
        active.cell = cell;
        active.original = controller.view;
        active.originalHidden = controller.view.hidden;
        active.replacement = replacement;
        objc_setAssociatedObject(replacement, ReplacementKey, active, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, ChartKey, active, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    IEBLayoutNativeChart(cell);
    return YES;
}
void IEBLayoutNativeChart(UITableViewCell *cell) {
    IEBChartAttachment *active = objc_getAssociatedObject(cell, ChartKey);
    UIView *replacement = active.replacement;
    UIView *original = active.original;
    if (!active || objc_getAssociatedObject(replacement, ReplacementKey) != active ||
        ![original isDescendantOfView:cell])
        return;
    original.hidden = YES;
    if (replacement.superview != original.superview)
        [original.superview addSubview:replacement];
    [original.superview bringSubviewToFront:replacement];
    if (original.bounds.size.width > 0 && original.bounds.size.height > 0)
        replacement.frame = original.frame;
    replacement.autoresizingMask = original.autoresizingMask;
}
void IEBRestoreNativeChart(UITableViewCell *cell) {
    RestoreAttachment(objc_getAssociatedObject(cell, ChartKey));
}
void IEBRestoreNativeChartView(UIView *replacement) {
    RestoreAttachment(objc_getAssociatedObject(replacement, ReplacementKey));
}

BOOL IEBNativeTimeUsageIsActive(UITableViewCell *cell) {
    return objc_getAssociatedObject(cell, TimesKey) != nil;
}

Class IEBNativeCellClassAtPath(id source, NSIndexPath *path) {
    SEL lookup = sel_registerName("specifierAtIndexPath:");
    Method lookupMethod = class_getInstanceMethod([source class], lookup);
    if (!source || !path || !lookupMethod || strcmp(method_getTypeEncoding(lookupMethod), "@24@0:8@16"))
        return Nil;
    id specifier = ((id(*)(id, SEL, id))objc_msgSend)(source, lookup, path);
    SEL property = sel_registerName("propertyForKey:");
    Method propertyMethod = class_getInstanceMethod([specifier class], property);
    if (!propertyMethod || strcmp(method_getTypeEncoding(propertyMethod), "@24@0:8@16"))
        return Nil;
    NSString *__unsafe_unretained *nativeKey =
        (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, "PSCellClassKey");
    NSString *key = nativeKey && [*nativeKey isKindOfClass:NSString.class] ? *nativeKey : @"cellClass";
    id value = ((id(*)(id, SEL, id))objc_msgSend)(specifier, property, key);
    Class cls = object_isClass(value)                  ? value
                : [value isKindOfClass:NSString.class] ? NSClassFromString(value)
                                                       : Nil;
    return cls && [cls isSubclassOfClass:UITableViewCell.class] ? cls : Nil;
}
