#import "IEBSessionState.h"
#import <math.h>

static BOOL ValidPower(NSInteger power) {
    return power >= IEBExternalPowerUnknown && power <= IEBExternalPowerAttached;
}
static BOOL ValidClock(double wall, double uptime) {
    return isfinite(wall) && wall > 0 && isfinite(uptime) && uptime >= 0;
}
static BOOL ValidBoot(id bootID) {
    return [bootID isKindOfClass:[NSString class]] && [bootID length] > 0 && [bootID length] <= 128;
}
static NSNumber *Number(id value) {
    return [value isKindOfClass:[NSNumber class]] &&
                   CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
                   isfinite([value doubleValue])
               ? value
               : nil;
}
static id Invalid(NSError **error, NSString *reason) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBSessionState"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : reason}];
    return nil;
}
@interface IEBSessionState ()
@property(nonatomic, readwrite) IEBExternalPower externalPower;
@property(nonatomic, readwrite) NSDate *start;
@property(nonatomic, readwrite) NSDate *end;
@property(nonatomic, readwrite) BOOL complete;
@property(nonatomic) NSString *bootID;
@property(nonatomic) double wallTime;
@property(nonatomic) double uptime;
@end

@implementation IEBSessionState
- (instancetype)init {
    self = [super init];
    if (self)
        _externalPower = IEBExternalPowerUnknown;
    return self;
}
- (IEBSessionState *)copyState {
    IEBSessionState *copy = [IEBSessionState new];
    copy.externalPower = self.externalPower;
    copy.start = self.start;
    copy.end = self.end;
    copy.complete = self.complete;
    copy.bootID = self.bootID;
    copy.wallTime = self.wallTime;
    copy.uptime = self.uptime;
    return copy;
}
- (void)invalidateActiveSession {
    if (self.start && !self.end) {
        self.end =
            [NSDate dateWithTimeIntervalSince1970:MAX(self.start.timeIntervalSince1970, self.wallTime)];
        self.complete = NO;
    }
}
- (IEBSessionState *)observingPower:(IEBExternalPower)power
                           wallTime:(double)wallTime
                             uptime:(double)uptime
                             bootID:(NSString *)bootID
                         continuous:(BOOL)continuous
                              error:(NSError **)error {
    if (error)
        *error = nil;
    if (!ValidPower(power) || !ValidClock(wallTime, uptime) || !ValidBoot(bootID))
        return Invalid(error, @"Invalid power observation or clock metadata");
    BOOL sameBoot = [self.bootID isEqual:bootID];
    if (sameBoot && uptime < self.uptime)
        return Invalid(error, @"Observation arrived out of monotonic order");
    BOOL reliable = self.bootID && sameBoot && continuous && wallTime >= self.wallTime &&
                    fabs((wallTime - self.wallTime) - (uptime - self.uptime)) <= 2 &&
                    self.externalPower != IEBExternalPowerUnknown && power != IEBExternalPowerUnknown;
    IEBSessionState *next = [self copyState];
    if (!reliable)
        [next invalidateActiveSession];
    if (reliable && self.externalPower == IEBExternalPowerAttached && power == IEBExternalPowerDetached) {
        next.start = [NSDate dateWithTimeIntervalSince1970:wallTime];
        next.end = nil;
        next.complete = YES;
    } else if (reliable && power == IEBExternalPowerAttached && next.start && !next.end) {
        next.end = [NSDate dateWithTimeIntervalSince1970:wallTime];
    }
    next.externalPower = power;
    next.wallTime = wallTime;
    next.uptime = uptime;
    next.bootID = [bootID copy];
    return next;
}
- (NSDictionary *)snapshot {
    NSMutableDictionary *value =
        [@{@"version" : @1, @"power" : @(self.externalPower), @"complete" : @(self.complete)} mutableCopy];
    if (self.bootID) {
        value[@"boot_id"] = self.bootID;
        value[@"wall_time"] = @(self.wallTime);
        value[@"uptime"] = @(self.uptime);
    }
    if (self.start)
        value[@"start"] = @(self.start.timeIntervalSince1970);
    if (self.end)
        value[@"end"] = @(self.end.timeIntervalSince1970);
    return value;
}
+ (IEBSessionState *)restoreSnapshot:(id)snapshot error:(NSError **)error {
    if (error)
        *error = nil;
    if (![snapshot isKindOfClass:[NSDictionary class]])
        return Invalid(error, @"Snapshot must be a dictionary");
    NSDictionary *value = snapshot;
    NSNumber *version = Number(value[@"version"]), *power = Number(value[@"power"]);
    id complete = value[@"complete"];
    if (![version isEqual:@1] || !power || power.doubleValue != floor(power.doubleValue) ||
        !ValidPower(power.integerValue) || ![complete isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)complete) != CFBooleanGetTypeID())
        return Invalid(error, @"Unknown snapshot version or invalid state");
    IEBSessionState *state = [IEBSessionState new];
    state.externalPower = power.integerValue;
    state.complete = [complete boolValue];
    BOOL hasObservation = value[@"boot_id"] != nil;
    if (hasObservation) {
        NSNumber *wall = Number(value[@"wall_time"]), *uptime = Number(value[@"uptime"]);
        if (!ValidBoot(value[@"boot_id"]) || !wall || !uptime ||
            !ValidClock(wall.doubleValue, uptime.doubleValue))
            return Invalid(error, @"Invalid snapshot clock metadata");
        state.bootID = [value[@"boot_id"] copy];
        state.wallTime = wall.doubleValue;
        state.uptime = uptime.doubleValue;
    } else if (state.externalPower != IEBExternalPowerUnknown || value[@"wall_time"] || value[@"uptime"])
        return Invalid(error, @"Missing snapshot observation metadata");
    NSNumber *start = Number(value[@"start"]), *end = Number(value[@"end"]);
    if ((value[@"start"] && (!start || start.doubleValue <= 0)) ||
        (value[@"end"] && (!end || !start || end.doubleValue < start.doubleValue)) ||
        ((start || state.complete) && !hasObservation) || (state.complete && !start) ||
        (start && !end && state.externalPower != IEBExternalPowerDetached))
        return Invalid(error, @"Invalid snapshot session boundaries");
    if (start)
        state.start = [NSDate dateWithTimeIntervalSince1970:start.doubleValue];
    if (end)
        state.end = [NSDate dateWithTimeIntervalSince1970:end.doubleValue];
    // A restored active session has an unobserved interval, even on the same boot.
    [state invalidateActiveSession];
    return state;
}
@end
