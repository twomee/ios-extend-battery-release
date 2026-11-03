#import "../Sources/Compatibility/IEBPlatformSupport.h"

#define C(...)                                                                                               \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Platform support FAIL %d: %s\n", __LINE__, #__VA_ARGS__);                       \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)

int main(void) {
    @autoreleasepool {
        C(IEBPlatformIsSupported(@"17.1.1", @"21B91"));
        for (NSString *version in @[ @"17.0", @"17.1", @"17.1.2", @"17.2", @"18.0" ]) {
            C(!IEBPlatformIsSupported(version, @"21B91"));
        }
        C(!IEBPlatformIsSupported(@"17.1.1", @"21B90"));
        C(!IEBPlatformIsSupported(@"17.1.1", @"21B92"));
        C(!IEBPlatformIsSupported(nil, @"21B91"));
        C(!IEBPlatformIsSupported(@"17.1.1", nil));
        C(!IEBPlatformIsSupported(nil, nil));
        for (NSString *version in
             @[ @"", @"17.1.1 ", @" 17.1.1", @"17.1.1\n", @"17.1.1.0", @"017.1.1", @"iOS 17.1.1" ]) {
            C(!IEBPlatformIsSupported(version, @"21B91"));
        }
        for (NSString *build in @[ @"", @"21b91", @"21B91 ", @" 21B91", @"21B91\n", @"21B91a" ]) {
            C(!IEBPlatformIsSupported(@"17.1.1", build));
        }
        C(!IEBPlatformIsSupported((id)NSNull.null, @"21B91"));
        C(!IEBPlatformIsSupported(@"17.1.1", (id)NSNull.null));
        C(!IEBPlatformIsSupported((id) @1711, @"21B91"));
        C(!IEBPlatformIsSupported(@"17.1.1", (id) @2191));
        puts("PASS exact platform version/build policy, adjacent releases, nil and malformed inputs");
        return 0;
    }
}
