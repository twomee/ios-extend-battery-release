#import "../Sources/Diagnostics/IEBProcessAttribution.h"
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Process join FAIL %d\n", __LINE__);                                             \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDictionary *Complete(NSArray *rows) {
    return @{
        @"rows" : rows,
        @"status" : @"available",
        @"unavailable_count" : @0,
        @"name_unavailable_count" : @0,
        @"enumeration_truncated" : @NO,
        @"enumerated_count" : @(rows.count)
    };
}
int main(void) {
    @autoreleasepool {
        NSArray *sources = @[
            @{@"id" : @"daemon",
              @"percent" : @5},
            @{@"id" : @"com.test.app",
              @"percent" : @10},
            @{@"id" : @"duplicate",
              @"percent" : @20}
        ];
        NSDictionary *catalog =
            @{@"com.test.app" : @{@"executable" : @"Sample", @"executable_unique" : @YES}};
        NSArray *rows = @[
            @{
                @"pid" : @1,
                @"name" : @"daemon",
                @"start_ticks" : @5,
                @"cpu_seconds" : @10,
                @"sampled_at" : @100
            },
            @{
                @"pid" : @2,
                @"name" : @"Sample",
                @"start_ticks" : @6,
                @"cpu_seconds" : @20,
                @"sampled_at" : @100
            },
            @{
                @"pid" : @3,
                @"name" : @"other",
                @"start_ticks" : @7,
                @"cpu_seconds" : @30,
                @"sampled_at" : @100
            },
            @{
                @"pid" : @4,
                @"name" : @"duplicate",
                @"start_ticks" : @8,
                @"cpu_seconds" : @10,
                @"sampled_at" : @100
            },
            @{
                @"pid" : @5,
                @"name" : @"duplicate",
                @"start_ticks" : @9,
                @"cpu_seconds" : @10,
                @"sampled_at" : @100
            }
        ];
        NSDictionary *r = IEBProcessAttribution(sources, catalog, Complete(rows), nil);
        C([r[@"sources"][@"daemon"][@"cpu_seconds"] doubleValue] == 10);
        C([r[@"sources"][@"com.test.app"][@"cpu_seconds"] doubleValue] == 20);
        C(!r[@"sources"][@"duplicate"]);
        C([r[@"processes"][0][@"energy_percent"] doubleValue] == 5);
        C(r[@"processes"][2][@"energy_percent"] == NSNull.null);
        C(r[@"processes"][3][@"energy_percent"] == NSNull.null);
        NSArray *ambiguous = [sources arrayByAddingObject:@{@"id" : @"com.test.second", @"percent" : @2}];
        NSMutableDictionary *ambCatalog = [catalog mutableCopy];
        ambCatalog[@"com.test.second"] = @{@"executable" : @"Sample", @"executable_unique" : @YES};
        r = IEBProcessAttribution(ambiguous, ambCatalog, Complete(rows), nil);
        C(!r[@"sources"][@"com.test.app"]);
        C(r[@"processes"][1][@"energy_percent"] == NSNull.null);
        NSDictionary *collision = IEBProcessAttribution(
            @[
                @{@"id" : @"com.test.app",
                  @"percent" : @10}
            ],
            @{@"com.test.app" : @{@"executable" : @"Sample", @"executable_unique" : @NO}},
            Complete(@[ rows[1] ]), nil);
        C(!collision[@"sources"][@"com.test.app"]);
        C(collision[@"processes"][0][@"energy_percent"] == NSNull.null);
        NSDictionary *partial = IEBProcessAttribution(
            sources, catalog, @{
                @"rows" : @[ rows[0] ],
                @"status" : @"partial",
                @"unavailable_count" : @1,
                @"name_unavailable_count" : @0,
                @"enumeration_truncated" : @NO,
                @"enumerated_count" : @2
            },
            nil);
        C(!partial[@"sources"][@"daemon"]);
        C(partial[@"processes"][0][@"energy_percent"] == NSNull.null);
        C([partial[@"processes"][0][@"cpu_seconds"] doubleValue] == 10);
        for (NSDictionary *change in @[
                 @{@"enumeration_truncated" : @YES},
                 @{@"name_unavailable_count" : @1},
                 @{@"enumerated_count" : @2}, @{@"status" : @"partial"}
             ]) {
            NSMutableDictionary *incomplete = [Complete(@[ rows[0] ]) mutableCopy];
            [incomplete addEntriesFromDictionary:change];
            NSDictionary *joined = IEBProcessAttribution(sources, catalog, incomplete, nil);
            C(!joined[@"sources"][@"daemon"]);
            C(joined[@"processes"][0][@"energy_percent"] == NSNull.null);
        }
        NSDictionary *unknown = IEBProcessAttribution(sources, catalog, @{@"rows" : @[ rows[0] ]}, nil);
        C(!unknown[@"sources"][@"daemon"]);
        puts("PASS unique process energy join, executable identity and ambiguity rejection");
        return 0;
    }
}
