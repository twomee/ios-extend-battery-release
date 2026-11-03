#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, IEBExternalPower) {
    IEBExternalPowerUnknown = -1,
    IEBExternalPowerDetached = 0,
    IEBExternalPowerAttached = 1,
};

// Immutable state. An absent start means no disconnect has been observed yet.
@interface IEBSessionState : NSObject
@property(nonatomic, readonly) IEBExternalPower externalPower;
@property(nonatomic, readonly) NSDate *start;
@property(nonatomic, readonly) NSDate *end;
@property(nonatomic, readonly) BOOL complete;
- (IEBSessionState *)observingPower:(IEBExternalPower)power
                           wallTime:(double)wallTime
                             uptime:(double)uptime
                             bootID:(NSString *)bootID
                         continuous:(BOOL)continuous
                              error:(NSError **)error;
- (NSDictionary *)snapshot;
+ (IEBSessionState *)restoreSnapshot:(id)snapshot error:(NSError **)error;
@end
