#import "../Sources/Statistics/IEBSourceGroups.h"
#import <Foundation/Foundation.h>
#define CHECK(x)                                                                                             \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "FAIL line %d\n", __LINE__);                                                     \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSArray *rows = @[
            @{@"id" : @"example.app",
              @"percent" : @60,
              @"foreground" : @30,
              @"background" : @15},
            @{@"id" : @"system.task",
              @"percent" : @30},
            @{@"id" : @"example.app.extension",
              @"percent" : @10}
        ];
        NSDictionary *catalog = @{
            @"example.app" : @{@"name" : @"Example", @"user_facing" : @YES},
            @"system.task" : @{@"name" : @"Hidden System", @"user_facing" : @NO}
        };
        NSDictionary *g = IEBSourceGroups(rows, catalog);
        CHECK([g[@"applications"] count] == 1 && [g[@"system_processes"] count] == 2);
        CHECK([g[@"applications"][0][@"background"] intValue] == 15);
        CHECK([g[@"applications"][0][@"percent"] intValue] == 60);
        CHECK([g[@"system_processes"][0][@"percent"] intValue] == 30);
        CHECK([g[@"system_processes"][1][@"id"] isEqual:@"example.app.extension"]);
        CHECK([IEBSourceGroups(rows, @{})[@"applications"] count] == 0);
        CHECK([IEBSourceGroups(@[], catalog)[@"system_processes"] count] == 0);
        CHECK([IEBSourceGroups(rows, @{@"system.task" : NSNull.null})[@"applications"] count] == 0);
        CHECK(IEBIsUserFacingApplication(
            @{@"CFBundleIdentifier" : @"com.apple.mobilesafari",
              @"UIBackgroundModes" : @[ @"audio" ]}));
        CHECK(!IEBIsUserFacingApplication(@{@"SBAppTags" : @[ @"hidden" ]}));
        CHECK(!IEBIsUserFacingApplication(@{@"LSBackgroundOnly" : @YES}));
        CHECK(!IEBIsUserFacingApplication(@{@"LSUIElement" : @YES}));
        CHECK(!IEBIsUserFacingApplication(@{@"SBIconVisibilityDefaultVisible" : @NO}));
        CHECK(!IEBIsUserFacingApplication(nil));
        CHECK(!IEBIsUserFacingApplication(@{@"SBAppTags" : @"malformed"}));
        CHECK(!IEBIsUserFacingApplication(@{@"LSUIElement" : @"malformed"}));
        puts("PASS installed application/system partition preserves identity, order and percentages");
        return 0;
    }
}
