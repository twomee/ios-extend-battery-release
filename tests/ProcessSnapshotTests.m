#import "../Sources/Diagnostics/IEBProcessSnapshot.h"
#import <math.h>
#define CHECK(x)                                                                                             \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "FAIL line %d\n", __LINE__);                                                     \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDictionary *Row(int pid, uint64_t start, double cpu, double sampled) {
    return @{@"pid" : @(pid), @"start_ticks" : @(start), @"cpu_seconds" : @(cpu), @"sampled_at" : @(sampled)};
}
int main(void) {
    @autoreleasepool {
        CHECK(fabs(IEBProcessTicksToSeconds(24000000, 125, 3) - 1) < 0.000001);
        CHECK(isnan(IEBProcessTicksToSeconds(1, 1, 0)));
        CHECK(isnan(IEBProcessTicksToSeconds(1, 0, 1)));
        NSDictionary *before = Row(7, 20, 10, 100);
        NSDictionary *after = Row(7, 20, 11, 102);
        NSDictionary *delta = IEBProcessCPUDelta(before, after);
        CHECK([delta[@"cpu_seconds"] doubleValue] == 1);
        CHECK([delta[@"window_seconds"] doubleValue] == 2);
        CHECK([delta[@"cpu_percent"] doubleValue] == 50);
        CHECK([IEBProcessCPUDelta(before, Row(7, 20, 14, 102))[@"cpu_percent"] doubleValue] == 200);
        CHECK(IEBProcessCPUDelta(before, Row(7, 21, 11, 102)) == nil);
        CHECK(IEBProcessCPUDelta(before, Row(8, 20, 11, 102)) == nil);
        CHECK(IEBProcessCPUDelta(before, Row(7, 20, 9, 102)) == nil);
        CHECK(IEBProcessCPUDelta(before, Row(7, 20, 11, 100)) == nil);
        CHECK(IEBProcessCPUDelta(before, Row(7, 20, 11, 99)) == nil);
        CHECK(IEBProcessCPUDelta(nil, after) == nil);
        CHECK(IEBProcessCPUDelta(@{}, after) == nil);
        CHECK(IEBProcessCPUDelta(before, Row(7, 20, NAN, 102)) == nil);
        CHECK(IEBProcessCPUDelta(before, Row(7, 20, 11, INFINITY)) == nil);
        CHECK(IEBProcessCPUDelta(Row(7, 0, 10, 100), Row(7, 0, 11, 102)) == nil);
        CHECK(IEBProcessCPUDelta(Row(7, 20, -1, 100), after) == nil);
        CHECK(IEBProcessCPUDelta(@{@"pid" : @"bad"}, after) == nil);
        CHECK(IEBProcessCPUDelta(
                  @{@"pid" : @7.5,
                    @"start_ticks" : @20,
                    @"cpu_seconds" : @10,
                    @"sampled_at" : @100},
                  @{@"pid" : @7.5,
                    @"start_ticks" : @20,
                    @"cpu_seconds" : @11,
                    @"sampled_at" : @102}) == nil);
        CHECK(IEBProcessCPUDelta(
                  @{@"pid" : @7,
                    @"start_ticks" : @(-1),
                    @"cpu_seconds" : @10,
                    @"sampled_at" : @100},
                  @{@"pid" : @7,
                    @"start_ticks" : @(-1),
                    @"cpu_seconds" : @11,
                    @"sampled_at" : @102}) == nil);
        NSDictionary *snapshot = IEBReadProcessSnapshot();
        CHECK([snapshot[@"rows"] isKindOfClass:NSArray.class]);
        CHECK([snapshot[@"status"] isKindOfClass:NSString.class]);
        CHECK([snapshot[@"cpu_scope"] isEqual:@"process_lifetime"]);
        CHECK([snapshot[@"battery_attribution"] isEqual:@"unavailable"]);
        puts("PASS process clock conversion, sample deltas, restart and invalid rejection, live collector "
             "contract");
    }
    return 0;
}
