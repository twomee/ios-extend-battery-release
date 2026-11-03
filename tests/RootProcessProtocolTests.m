#import "../Sources/Diagnostics/IEBRootProcessProtocol.h"
#import <math.h>
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Root protocol FAIL %d\n", __LINE__);                                            \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSData *Payload(id envelope) {
    return [NSPropertyListSerialization dataWithPropertyList:envelope
                                                      format:NSPropertyListBinaryFormat_v1_0
                                                     options:0
                                                       error:NULL];
}
int main(void) {
    @autoreleasepool {
        C(IEBRootProcessCallerAllowed(0, nil, 0));
        C(IEBRootProcessCallerAllowed(501, @"com.apple.Preferences", 0x04000001));
        C(!IEBRootProcessCallerAllowed(501, @"com.apple.Preferences", 1));
        C(!IEBRootProcessCallerAllowed(501, @"other", 0x04000001));
        C(!IEBRootProcessCallerAllowed(502, @"com.apple.Preferences", 0x04000001));
        C(!IEBRootProcessCallerAllowed(501, nil, 0));
        C(IEBRootProcessRequestValid(@{@"version" : @1, @"operation" : @"snapshot"}));
        C(!IEBRootProcessRequestValid(@{@"version" : @YES, @"operation" : @"snapshot"}));
        C(!IEBRootProcessRequestValid(@{@"version" : @2, @"operation" : @"snapshot"}));
        C(!IEBRootProcessRequestValid(@{@"version" : @1, @"operation" : @"kill"}));
        C(!IEBRootProcessRequestValid(
            @{@"version" : @1,
              @"operation" : @"snapshot",
              @"path" : @"/tmp/file"}));
        NSDictionary *row = @{
            @"pid" : @5,
            @"name" : @"fixture",
            @"start_ticks" : @24,
            @"cpu_seconds" : @1.5,
            @"sampled_at" : @100
        };
        NSMutableDictionary *snapshot = [@{
            @"rows" : @[ row ],
            @"status" : @"available",
            @"cpu_scope" : @"process_lifetime",
            @"cpu_unit" : @"seconds",
            @"cpu_source" : @"proc_pid_rusage_v2_mach_absolute",
            @"battery_attribution" : @"unavailable",
            @"enumerated_count" : @1,
            @"unavailable_count" : @0,
            @"permission_denied_count" : @0,
            @"vanished_count" : @0,
            @"name_unavailable_count" : @0,
            @"enumeration_truncated" : @NO,
            @"timebase_numerator" : @125,
            @"timebase_denominator" : @3
        } mutableCopy];
        NSError *error = nil;
        NSData *data = IEBEncodeRootProcessSnapshot(snapshot, &error);
        NSDictionary *decoded = IEBDecodeRootProcessSnapshot(data, &error);
        C(decoded && !error && [decoded[@"rows"] count] == 1);
        C([decoded[@"reader_provider"] isEqual:@"root-service"]);
        NSMutableDictionary *bad = [snapshot mutableCopy];
        bad[@"rows"] = @[ row, row ];
        bad[@"enumerated_count"] = @2;
        C(!IEBEncodeRootProcessSnapshot(bad, &error) && error);
        bad = [snapshot mutableCopy];
        bad[@"enumerated_count"] = @YES;
        C(!IEBEncodeRootProcessSnapshot(bad, &error));
        bad = [snapshot mutableCopy];
        bad[@"rows"] = @[ @{
            @"pid" : @(-1),
            @"name" : @"fixture",
            @"start_ticks" : @24,
            @"cpu_seconds" : @1.5,
            @"sampled_at" : @100
        } ];
        C(!IEBEncodeRootProcessSnapshot(bad, &error));
        bad = [snapshot mutableCopy];
        bad[@"rows"] = @[ @{
            @"pid" : @5,
            @"name" : @"fixture",
            @"start_ticks" : @24,
            @"cpu_seconds" : @(NAN),
            @"sampled_at" : @100
        } ];
        C(!IEBEncodeRootProcessSnapshot(bad, &error));
        C(!IEBDecodeRootProcessSnapshot(Payload(@{@"version" : @2, @"snapshot" : snapshot}), &error));
        C(!IEBDecodeRootProcessSnapshot([NSMutableData dataWithLength:2097153], &error));
        C(!IEBDecodeRootProcessSnapshot([@"invalid" dataUsingEncoding:NSUTF8StringEncoding], &error));
        puts("PASS root caller policy, request allowlist, bounded payload and corrupt snapshot rejection");
        return 0;
    }
}
