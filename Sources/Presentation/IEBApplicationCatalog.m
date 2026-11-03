#import "IEBApplicationCatalog.h"
#import "../Statistics/IEBSourceGroups.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
static BOOL ABI(Class cls, NSString *selector, BOOL classMethod, const char *encoding) {
    Method m = classMethod ? class_getClassMethod(cls, NSSelectorFromString(selector))
                           : class_getInstanceMethod(cls, NSSelectorFromString(selector));
    return m && strcmp(method_getTypeEncoding(m), encoding) == 0;
}
static id Get(id target, NSString *selector) {
    return ((id (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(selector));
}
NSDictionary *IEBLoadApplicationCatalog(NSArray<NSString *> *identities) {
    static NSDictionary *installed;
    static double updated;
    static NSCache *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
        icons = [NSCache new];
        icons.countLimit = 128;
    });
    @synchronized(icons) {
        double now = NSProcessInfo.processInfo.systemUptime;
        if (updated == 0 || now - updated > 60) {
            NSMutableDictionary *catalog = [NSMutableDictionary new];
            Class workspace = NSClassFromString(@"LSApplicationWorkspace"),
                  proxy = NSClassFromString(@"LSApplicationProxy");
            BOOL supported =
                ABI(workspace, @"defaultWorkspace", YES, "@16@0:8") &&
                ABI(workspace, @"allInstalledApplications", NO, "@16@0:8") &&
                ABI(proxy, @"bundleIdentifier", NO, "@16@0:8") && ABI(proxy, @"bundleURL", NO, "@16@0:8") &&
                ABI(proxy, @"localizedName", NO, "@16@0:8") && ABI(proxy, @"isInstalled", NO, "B16@0:8");
            if (supported)
                @try {
                    id apps = Get(Get(workspace, @"defaultWorkspace"), @"allInstalledApplications");
                    if ([apps isKindOfClass:NSArray.class] && [apps count] <= 10000)
                        for (id app in apps) {
                            id identity = Get(app, @"bundleIdentifier"), url = Get(app, @"bundleURL"),
                               name = Get(app, @"localizedName");
                            BOOL present =
                                ((BOOL (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"isInstalled"));
                            if (present && [identity isKindOfClass:NSString.class] && [identity length] > 0 &&
                                [url isKindOfClass:NSURL.class] && [[url pathExtension] isEqual:@"app"]) {
                                NSError *infoError = nil;
                                NSData *data = [NSData
                                    dataWithContentsOfURL:[url URLByAppendingPathComponent:@"Info.plist"]
                                                  options:NSDataReadingMappedIfSafe
                                                    error:&infoError];
                                id info = data && data.length <= 1048576
                                              ? [NSPropertyListSerialization
                                                    propertyListWithData:data
                                                                 options:NSPropertyListImmutable
                                                                  format:NULL
                                                                   error:&infoError]
                                              : nil;
                                BOOL known = [info isKindOfClass:NSDictionary.class];
                                catalog[identity] = @{
                                    @"user_facing" : @(known && IEBIsUserFacingApplication(info)),
                                    @"classification_available" : @(known),
                                    @"executable" : known &&
                                            [info[@"CFBundleExecutable"] isKindOfClass:NSString.class]
                                        ? info[@"CFBundleExecutable"]
                                        : @"",
                                    @"name" : [name isKindOfClass:NSString.class] && [name length] ? name
                                                                                                   : identity
                                };
                            }
                        }
                } @catch (NSException *exception) {
                    (void)exception;
                    [catalog removeAllObjects];
                }
            // Check all installed bundles, including those absent from this energy window.
            NSMutableDictionary *executableCounts = [NSMutableDictionary new];
            for (NSDictionary *entry in catalog.allValues) {
                NSString *exe = entry[@"executable"];
                if (exe.length)
                    executableCounts[exe] = @([executableCounts[exe] unsignedIntegerValue] + 1);
            }
            for (NSString *identity in catalog.allKeys) {
                NSMutableDictionary *entry = [catalog[identity] mutableCopy];
                entry[@"executable_unique"] =
                    @([entry[@"executable"] length] &&
                      [executableCounts[entry[@"executable"]] unsignedIntegerValue] == 1);
                catalog[identity] = entry;
            }
            installed = catalog.count ? [catalog copy] : nil;
            updated = now;
        }
        if (!installed)
            return nil;
        NSMutableDictionary *result = [NSMutableDictionary new];
        BOOL iconSupported =
            ABI(UIImage.class, @"_applicationIconImageForBundleIdentifier:format:scale:", YES,
                "@36@0:8@16i24d28");
        for (NSString *identity in identities) {
            if (!installed[identity])
                continue;
            NSMutableDictionary *item = [installed[identity] mutableCopy];
            UIImage *icon = [icons objectForKey:identity];
            if (!icon && iconSupported)
                @try {
                    UIImage *source = ((id (*)(id, SEL, id, int, double))objc_msgSend)(
                        UIImage.class,
                        NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"),
                        identity, 0, 2.0);
                    if ([source isKindOfClass:UIImage.class] && source.size.width > 0 &&
                        source.size.height > 0) {
                        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
                        format.scale = 2;
                        UIGraphicsImageRenderer *renderer =
                            [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32) format:format];
                        icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                            (void)ctx;
                            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 32, 32)
                                                        cornerRadius:7] addClip];
                            [source drawInRect:CGRectMake(0, 0, 32, 32)];
                        }];
                        [icons setObject:icon forKey:identity];
                    }
                } @catch (NSException *exception) {
                    (void)exception;
                }
            item[@"icon_is_native"] = @(icon != nil);
            item[@"icon"] = icon ?: [UIImage systemImageNamed:@"app"];
            result[identity] = item;
        }
        return [result copy];
    }
}
