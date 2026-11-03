#import "IEBSessionState.h"

// Start/stop on the same run-loop thread. Handler runs there too.
// Keep the observer alive until stop. Each delivery is an observed edge, not a
// guarantee of physical edge timing or delivery of coalesced hardware events.
@interface IEBPowerObserver : NSObject
@property(nonatomic, readonly) IEBSessionState *state;
- (instancetype)initWithState:(IEBSessionState *)state
                      handler:(void (^)(IEBSessionState *state, NSError *error))handler;
- (BOOL)start:(NSError **)error;
- (void)stop;
@end
