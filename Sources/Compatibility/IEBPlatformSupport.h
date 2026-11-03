#ifndef IEB_PLATFORM_SUPPORT_H
#define IEB_PLATFORM_SUPPORT_H

#import <Foundation/Foundation.h>

static NSString *const IEBSupportedProductVersion = @"17.1.1";
static NSString *const IEBSupportedProductBuildVersion = @"21B91";

// Runtime admission policy only; callers must still verify their private APIs.
static inline BOOL IEBPlatformIsSupported(NSString *version, NSString *build) {
    return [version isKindOfClass:NSString.class] && [build isKindOfClass:NSString.class] &&
           [version isEqualToString:IEBSupportedProductVersion] &&
           [build isEqualToString:IEBSupportedProductBuildVersion];
}

#endif
