#import "../Sources/Compatibility/IEBPlatformSupport.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import "../tools/IEBProducerEvidence.h"
#import "IEBActivityCapture.h"
#import "IEBNativeCapture.h"
#import <objc/message.h>
#import <unistd.h>

@interface PLBatteryUIResponderService : NSObject
- (NSDictionary *)configuration;
@end

%group IEBProducerHooks
%hook PLBatteryUIResponderService
- (id)convertResponseToLegacyFormat:(id)raw {
    NSDictionary *configuration = [self configuration];
    NSDictionary *evidence = nil;
    if (IEBIsProducerProbe(configuration)) {
        @try {
            evidence = IEBProducerEvidence(raw, configuration);
        } @catch (NSException *exception) {
            (void)exception;
            evidence = @{@"schema_version": @1, @"diagnostic_error": @YES};
        }
    }
    id legacy = %orig;
    if (!evidence || ![legacy isKindOfClass:[NSDictionary class]]) return legacy;
    NSMutableDictionary *response = [legacy mutableCopy];
    response[@"IEBProducerEvidence"] = evidence;
    return response;
}
%end
%end

%group IEBNativeActivityHooks
%hook PLAppTimeService
- (void)logProportionateAggregateEntry:(id)entry withStartDate:(id)start withEndDate:(id)end {
    %orig;
    IEBObserveActivityAggregate(entry, start, end);
}
%end
%end

%group IEBNativePowerHooks
%hook PLAppTimeService
- (void)handleBatteryCallback:(id)callback {
    @try {
        id entry = [callback objectForKeyedSubscript:@"entry"];
        id connected = [entry objectForKeyedSubscript:@"ExternalConnected"];
        NSDate *date = ((id (*)(id, SEL))objc_msgSend)(entry, sel_registerName("entryDate"));
        IEBObserveNativePower(connected, date);
    } @catch (NSException *exception) {
        (void)exception;
        IEBObserveNativePower(nil, nil);
    }
    %orig;
}
%end
%end

static BOOL activityAttempted;
static void InstallActivityHooks(void) {
    if (activityAttempted || getuid() != 501 || ![NSProcessInfo.processInfo.processName isEqual:@"PerfPowerServices"]) return;
    Class cls = NSClassFromString(@"PLAppTimeService");
    if (!cls) return;
    activityAttempted = YES;
    Method log = class_getInstanceMethod(cls, @selector(logProportionateAggregateEntry:withStartDate:withEndDate:));
    Method subscript = class_getInstanceMethod(NSClassFromString(@"PLEntry"), @selector(objectForKeyedSubscript:));
    BOOL abi = log && subscript && strcmp(method_getTypeEncoding(log), "v40@0:8@16@24@32") == 0 &&
        strcmp(method_getTypeEncoding(subscript), "@24@0:8@16") == 0;
    Method power = class_getInstanceMethod(cls, sel_registerName("handleBatteryCallback:"));
    Method entryDate = class_getInstanceMethod(NSClassFromString(@"PLEntry"), sel_registerName("entryDate"));
    Method clock = class_getClassMethod(NSDate.class, sel_registerName("monotonicDate"));
    BOOL nativeABI = abi && power && entryDate && clock &&
        strcmp(method_getTypeEncoding(power), "v24@0:8@16") == 0 &&
        strcmp(method_getTypeEncoding(entryDate), "@16@0:8") == 0 &&
        strcmp(method_getTypeEncoding(clock), "@16@0:8") == 0;
    if (abi) { %init(IEBNativeActivityHooks); }
    if (nativeABI) { %init(IEBNativePowerHooks); }
    dispatch_async(dispatch_get_main_queue(), ^{
        IEBStartActivityCapture(abi);
        NSDate *(^provider)(void) = nativeABI ? ^NSDate *{
            return ((id (*)(id, SEL))objc_msgSend)(NSDate.class, sel_registerName("monotonicDate"));
        } : nil;
        IEBStartNativeCapture(provider);
    });
}

static BOOL installed;
static void InstallHooks(void) {
    NSDictionary *version = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    if (!IEBPlatformIsSupported(version[@"ProductVersion"], version[@"ProductBuildVersion"])) return;
    InstallActivityHooks();
    if (installed) return;
    Class cls = NSClassFromString(@"PLBatteryUIResponderService");
    Method convert = class_getInstanceMethod(cls, @selector(convertResponseToLegacyFormat:));
    Method configuration = class_getInstanceMethod(cls, @selector(configuration));
    if (!convert || !configuration || strcmp(method_getTypeEncoding(convert), "@24@0:8@16") != 0 ||
        strcmp(method_getTypeEncoding(configuration), "@16@0:8") != 0) return;
    %init(IEBProducerHooks);
    installed = YES;
}

static void ImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)slide;
    Dl_info info;
    if (dladdr(header, &info) && info.dli_fname && strstr(info.dli_fname, "PowerlogHelperdOperators"))
        dispatch_async(dispatch_get_main_queue(), ^{ InstallHooks(); });
}

%ctor {
    @autoreleasepool {
        _dyld_register_func_for_add_image(ImageAdded);
        InstallHooks();
    }
}
