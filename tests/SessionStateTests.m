#import "../Sources/Session/IEBSessionState.h"
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Session FAIL %d: %s\n", __LINE__, #c);                                          \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static IEBSessionState *Observe(IEBSessionState *state, IEBExternalPower power, double wall, double uptime) {
    NSError *error = nil;
    IEBSessionState *next = [state observingPower:power
                                         wallTime:wall
                                           uptime:uptime
                                           bootID:@"boot-a"
                                       continuous:YES
                                            error:&error];
    if (!next || error)
        fprintf(stderr, "Unexpected session error: %s\n", error.description.UTF8String);
    return next;
}
int main(void) {
    @autoreleasepool {
        IEBSessionState *fresh = [IEBSessionState new];
        REQUIRE(fresh.externalPower == IEBExternalPowerUnknown);
        IEBSessionState *attached = Observe(fresh, IEBExternalPowerAttached, 1000, 100);
        REQUIRE(attached && attached.start == nil);
        IEBSessionState *active = Observe(attached, IEBExternalPowerDetached, 1010, 110);
        REQUIRE(active.complete && active.start.timeIntervalSince1970 == 1010 && active.end == nil);
        REQUIRE(attached.start == nil); // old immutable state retained
        IEBSessionState *same = Observe(active, IEBExternalPowerDetached, 1020, 120);
        REQUIRE([same.start isEqual:active.start]);
        IEBSessionState *frozen = Observe(same, IEBExternalPowerAttached, 1030, 130);
        REQUIRE(frozen.complete && frozen.end.timeIntervalSince1970 == 1030);
        REQUIRE([Observe(frozen, IEBExternalPowerAttached, 1040, 140).end isEqual:frozen.end]);
        IEBSessionState *next = Observe(frozen, IEBExternalPowerDetached, 1041, 141);
        REQUIRE(next.complete && next.start.timeIntervalSince1970 == 1041 && !next.end);
        IEBSessionState *initialDetached = Observe(fresh, IEBExternalPowerDetached, 1000, 100);
        REQUIRE(!initialDetached.start && !initialDetached.complete);
        IEBSessionState *unknown = Observe(active, IEBExternalPowerUnknown, 1020, 120);
        REQUIRE(!unknown.complete && unknown.end.timeIntervalSince1970 == 1010);
        REQUIRE(!Observe(unknown, IEBExternalPowerDetached, 1030, 130).complete);
        IEBSessionState *gap = [active observingPower:IEBExternalPowerDetached
                                             wallTime:1020
                                               uptime:120
                                               bootID:@"boot-a"
                                           continuous:NO
                                                error:NULL];
        REQUIRE(!gap.complete && gap.end.timeIntervalSince1970 == 1010);
        IEBSessionState *reboot = [active observingPower:IEBExternalPowerDetached
                                                wallTime:1030
                                                  uptime:1
                                                  bootID:@"boot-b"
                                              continuous:YES
                                                   error:NULL];
        REQUIRE(!reboot.complete && reboot.end);
        IEBSessionState *jump = Observe(active, IEBExternalPowerDetached, 1200, 120);
        REQUIRE(!jump.complete && jump.end);
        IEBSessionState *rollback = Observe(active, IEBExternalPowerDetached, 900, 120);
        REQUIRE(!rollback.complete &&
                rollback.end.timeIntervalSince1970 >= rollback.start.timeIntervalSince1970);
        IEBSessionState *smallRollback = Observe(active, IEBExternalPowerAttached, 1009, 111);
        REQUIRE(!smallRollback.complete);
        REQUIRE(smallRollback.end.timeIntervalSince1970 >= smallRollback.start.timeIntervalSince1970);
        REQUIRE([IEBSessionState restoreSnapshot:[smallRollback snapshot] error:NULL] != nil);
        NSError *error = nil;
        REQUIRE([active observingPower:IEBExternalPowerDetached
                              wallTime:1011
                                uptime:109
                                bootID:@"boot-a"
                            continuous:YES
                                 error:&error] == nil);
        REQUIRE(error != nil);
        error = nil;
        REQUIRE([active observingPower:IEBExternalPowerDetached
                              wallTime:NAN
                                uptime:120
                                bootID:@"boot-a"
                            continuous:YES
                                 error:&error] == nil &&
                error);
        REQUIRE([active observingPower:42
                              wallTime:1020
                                uptime:120
                                bootID:@"boot-a"
                            continuous:YES
                                 error:NULL] == nil);
        REQUIRE([active observingPower:IEBExternalPowerDetached
                              wallTime:1020
                                uptime:120
                                bootID:@""
                            continuous:YES
                                 error:NULL] == nil);
        NSDictionary *snapshot = [active snapshot];
        REQUIRE([NSPropertyListSerialization propertyList:snapshot
                                         isValidForFormat:NSPropertyListBinaryFormat_v1_0]);
        IEBSessionState *restored = [IEBSessionState restoreSnapshot:snapshot error:NULL];
        REQUIRE(restored && !restored.complete && restored.end.timeIntervalSince1970 == 1010);
        IEBSessionState *restoredFrozen = [IEBSessionState restoreSnapshot:[frozen snapshot] error:NULL];
        REQUIRE(restoredFrozen.complete && [restoredFrozen.end isEqual:frozen.end]);
        REQUIRE([IEBSessionState restoreSnapshot:@{@"version" : @2} error:NULL] == nil);
        REQUIRE([IEBSessionState restoreSnapshot:@[] error:NULL] == nil);
        REQUIRE(([IEBSessionState restoreSnapshot:@{@"version" : @1, @"power" : @42} error:NULL] == nil));
        REQUIRE([IEBSessionState restoreSnapshot:[fresh snapshot] error:NULL] != nil);
        NSMutableDictionary *badSnapshot = [[frozen snapshot] mutableCopy];
        badSnapshot[@"start"] = @YES;
        REQUIRE([IEBSessionState restoreSnapshot:badSnapshot error:NULL] == nil);
        badSnapshot = [[frozen snapshot] mutableCopy];
        badSnapshot[@"end"] = @900;
        REQUIRE([IEBSessionState restoreSnapshot:badSnapshot error:NULL] == nil);
        badSnapshot = [[frozen snapshot] mutableCopy];
        badSnapshot[@"uptime"] = @(NAN);
        REQUIRE([IEBSessionState restoreSnapshot:badSnapshot error:NULL] == nil);
        REQUIRE([Observe(Observe(gap, IEBExternalPowerAttached, 1030, 130), IEBExternalPowerDetached, 1040,
                         140) complete]);
        puts("PASS session state transitions, gaps, clocks, snapshots");
    }
    return 0;
}
