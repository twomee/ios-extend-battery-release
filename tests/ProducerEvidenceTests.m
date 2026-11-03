#import "../tools/IEBProducerEvidence.h"

#define REQUIRE(condition)                                                                                   \
    do {                                                                                                     \
        if (!(condition)) {                                                                                  \
            fprintf(stderr, "Producer FAIL line %d: %s\n", __LINE__, #condition);                            \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)

int IEBRunProducerEvidenceTests(void) {
    NSDictionary *request =
        @{@"enum" : @1,
          @"start" : @1000,
          @"end" : @2237,
          @"bucket" : @1237,
          @"IEBProbeVersion" : @1};
    NSDictionary *configuration = @{@"BatteryBreakdown_UnknownRange" : request, @"skipPlistWriteKey" : @1};
    REQUIRE(!IEBIsProducerProbe(nil));
    REQUIRE(!IEBIsProducerProbe(@[]));
    REQUIRE(!IEBIsProducerProbe(@{@"request" : @{@"IEBProbeVersion" : @YES}}));
    REQUIRE(IEBIsProducerProbe(configuration));
    REQUIRE(!IEBIsProducerProbe(@{@"BatteryBreakdown_UnknownRange" : request}));
    REQUIRE(!IEBIsProducerProbe(@{@"BatteryBreakdown_UnknownRange" : request, @"skipPlistWriteKey" : @0}));
    NSMutableDictionary *bad = [request mutableCopy];
    bad[@"start"] = @(NAN);
    REQUIRE(!IEBIsProducerProbe(@{@"request" : bad}));
    bad[@"start"] = @2238;
    REQUIRE(!IEBIsProducerProbe(@{@"request" : bad}));
    bad[@"start"] = @1000;
    bad[@"IEBProbeVersion"] = @2;
    REQUIRE(!IEBIsProducerProbe(@{@"request" : bad}));

    NSDictionary *bucket = @{
        @"PLBatteryUIBucketStartKey" : @1000,
        @"PLBatteryUIBucketEndKey" : @2237,
        @"PLBatteryUIAppArrayKey" : @[ @{@"PLBatteryUIAppBundleIDKey" : @"secret.app"} ]
    };
    NSDictionary *raw = @{
        @"BatteryBreakdown" : @{@"UnknownRange" : @{@"result" : @{@"PLBatteryUIBreakdownKey" : @[ bucket ]}}}
    };
    NSDictionary *evidence = IEBProducerEvidence(raw, configuration);
    REQUIRE([evidence[@"requests"] count] == 1);
    NSDictionary *row = [evidence[@"requests"] firstObject];
    REQUIRE([row[@"result_present"] isEqual:@YES]);
    REQUIRE([row[@"bucket_count"] isEqual:@1]);
    REQUIRE([row[@"app_entry_count"] isEqual:@1]);
    REQUIRE([row[@"outside_bucket_count"] isEqual:@0]);
    REQUIRE([row[@"missing_boundary_count"] isEqual:@0]);
    REQUIRE([row[@"earliest_bucket_start"] isEqual:@1000]);
    REQUIRE([row[@"latest_bucket_end"] isEqual:@2237]);
    REQUIRE(![evidence.description containsString:@"secret.app"]);
    REQUIRE(![evidence.description containsString:@"PLBatteryUIAppBundleIDKey"]);
    REQUIRE([NSJSONSerialization isValidJSONObject:evidence]);
    REQUIRE([NSPropertyListSerialization propertyList:evidence
                                     isValidForFormat:NSPropertyListBinaryFormat_v1_0]);
    REQUIRE([NSPropertyListSerialization propertyList:IEBProducerEvidence(@{}, configuration)
                                     isValidForFormat:NSPropertyListBinaryFormat_v1_0]);

    // Native raw keys describe range/bucket, without the client response-type prefix.
    for (NSDictionary *fixture in @[
             @{@"span" : @86400,
               @"bucket" : @86400,
               @"key" : @"24hr"},
             @{@"span" : @86400,
               @"bucket" : @3600,
               @"key" : @"24hr_3600"},
             @{@"span" : @604800,
               @"bucket" : @604800,
               @"key" : @"7d"},
             @{@"span" : @864000,
               @"bucket" : @864000,
               @"key" : @"10d"},
             @{@"span" : @3600,
               @"bucket" : @3600,
               @"key" : @"1hr"},
             @{@"span" : @1237,
               @"bucket" : @3600,
               @"key" : @"UnknownRange_3600"},
             @{@"span" : @0.25,
               @"bucket" : @0.25,
               @"key" : @"UnknownRange"},
             @{@"span" : @1237,
               @"bucket" : @123.75,
               @"key" : @"UnknownRange_123"}
         ]) {
        NSMutableDictionary *configured = [request mutableCopy];
        configured[@"end"] = @(1000 + [fixture[@"span"] doubleValue]);
        configured[@"bucket"] = fixture[@"bucket"];
        NSDictionary *native = @{
            @"BatteryBreakdown" :
                @{fixture[@"key"] : @{@"result" : @{@"PLBatteryUIBreakdownKey" : @[ bucket ]}}}
        };
        NSDictionary *observed = IEBProducerEvidence(
            native,
            @{@"client-key-is-not-a-producer-key" : configured,
              @"skipPlistWriteKey" : @1})[@"requests"][0];
        REQUIRE([observed[@"result_present"] isEqual:@YES]);
        REQUIRE([observed[@"bucket_count"] isEqual:@1]);
    }

    NSDictionary *missing = IEBProducerEvidence(@{}, configuration);
    REQUIRE(missing[@"requests"][0][@"app_entry_count"] == nil);
    REQUIRE([missing[@"requests"][0][@"result_present"] isEqual:@NO]);
    NSDictionary *outside = @{
        @"PLBatteryUIBucketStartKey" : @999,
        @"PLBatteryUIBucketEndKey" : @2237,
        @"PLBatteryUIAppArrayKey" : @[]
    };
    NSDictionary *wrapped =
        @{@"BatteryBreakdown" : @{@"result" : @{@"PLBatteryUIBreakdownKey" : @[ outside, @{} ]}}};
    NSDictionary *outsideEvidence = IEBProducerEvidence(wrapped, configuration);
    REQUIRE([outsideEvidence[@"requests"][0][@"outside_bucket_count"] isEqual:@1]);
    REQUIRE([outsideEvidence[@"requests"][0][@"missing_boundary_count"] isEqual:@1]);
    REQUIRE([IEBProducerEvidence(raw, @{})[@"requests"] count] == 0);
    NSMutableDictionary *untrusted = [evidence mutableCopy];
    untrusted[@"unexpected_secret"] = @"private.app";
    NSMutableDictionary *untrustedRow = [row mutableCopy];
    untrustedRow[@"app_name"] = @"private.app";
    untrustedRow[@"bucket_count"] = @"untrusted-text";
    untrusted[@"requests"] = @[ untrustedRow ];
    NSDictionary *sanitized = IEBSanitizeProducerEvidence(untrusted);
    REQUIRE([sanitized[@"requests"] count] == 1);
    REQUIRE(![sanitized.description containsString:@"private.app"]);
    REQUIRE(![sanitized.description containsString:@"untrusted-text"]);
    REQUIRE([sanitized[@"requests"][0][@"bucket_count"] isEqual:[NSNull null]]);
    REQUIRE([IEBSanitizeProducerEvidence(@"bad")[@"available"] isEqual:@NO]);
    REQUIRE([IEBSanitizeProducerEvidence(@{@"schema_version" : @2})[@"available"] isEqual:@NO]);
    NSMutableDictionary *tooManyRequests = [NSMutableDictionary dictionaryWithObject:@1
                                                                              forKey:@"skipPlistWriteKey"];
    for (NSUInteger i = 0; i < 65; i++)
        tooManyRequests[[@(i) stringValue]] = request;
    REQUIRE(!IEBIsProducerProbe(tooManyRequests));
    REQUIRE([IEBProducerEvidence(raw, tooManyRequests)[@"limited"] isEqual:@YES]);
    NSMutableArray *tooManyBuckets = [NSMutableArray array];
    for (NSUInteger i = 0; i < 513; i++)
        [tooManyBuckets addObject:bucket];
    NSDictionary *largeRaw =
        @{@"BatteryBreakdown" : @{@"result" : @{@"PLBatteryUIBreakdownKey" : tooManyBuckets}}};
    NSDictionary *large = IEBProducerEvidence(largeRaw, configuration)[@"requests"][0];
    REQUIRE([large[@"truncated"] isEqual:@YES]);
    REQUIRE([large[@"bucket_count"] isEqual:@513]);
    REQUIRE(large[@"app_entry_count"] == nil);
    REQUIRE(large[@"earliest_bucket_start"] == nil);
    REQUIRE(outsideEvidence[@"requests"][0][@"earliest_bucket_start"] == nil);
    NSDictionary *usageRequest =
        @{@"enum" : @8,
          @"start" : @1000,
          @"end" : @2237,
          @"bucket" : @3600,
          @"IEBProbeVersion" : @1};
    NSDictionary *usageRaw = @{
        @"UsageTimes" : @{
            @"result" : @{
                @"PLBatteryUIScreenOnTimeKey" :
                    @{@"PLBatteryUIGraphByBucket" : @[ @10, @20 ], @"PLBatteryUIGraphTotal" : @30},
                @"PLBatteryUIScreenOffTimeKey" :
                    @{@"PLBatteryUIGraphByBucket" : @[ @40, @50 ], @"PLBatteryUIGraphTotal" : @90}
            }
        }
    };
    NSDictionary *usage = IEBProducerEvidence(
        usageRaw,
        @{@"usage" : usageRequest,
          @"skipPlistWriteKey" : @1})[@"requests"][0];
    REQUIRE([usage[@"screen_on_bucket_count"] isEqual:@2]);
    REQUIRE([usage[@"screen_off_bucket_count"] isEqual:@2]);
    REQUIRE([usage[@"screen_on_seconds"] isEqual:@30]);
    REQUIRE([usage[@"screen_off_seconds"] isEqual:@90]);
    NSDictionary *badUsageRaw = @{
        @"UsageTimes" : @{
            @"result" : @{
                @"PLBatteryUIScreenOnTimeKey" :
                    @{@"PLBatteryUIGraphByBucket" : @"invalid", @"PLBatteryUIGraphTotal" : @YES},
                @"PLBatteryUIScreenOffTimeKey" :
                    @{@"PLBatteryUIGraphByBucket" : @{}, @"PLBatteryUIGraphTotal" : @(-1)}
            }
        }
    };
    NSDictionary *badUsage = IEBProducerEvidence(
        badUsageRaw,
        @{@"usage" : usageRequest,
          @"skipPlistWriteKey" : @1})[@"requests"][0];
    REQUIRE(badUsage[@"screen_on_bucket_count"] == nil);
    REQUIRE(badUsage[@"screen_off_bucket_count"] == nil);
    REQUIRE(badUsage[@"screen_on_seconds"] == nil);
    REQUIRE(badUsage[@"screen_off_seconds"] == nil);
    NSDictionary *safeUsage = IEBSanitizeProducerEvidence(
        @{@"schema_version" : @1,
          @"requests" : @[ usage ]});
    REQUIRE([safeUsage[@"requests"][0][@"screen_on_seconds"] isEqual:@30]);
    REQUIRE([IEBSanitizeProducerEvidence(evidence)[@"requests"][0][@"earliest_bucket_start"] isEqual:@1000]);
    puts("PASS producer evidence checks");
    return 0;
}
