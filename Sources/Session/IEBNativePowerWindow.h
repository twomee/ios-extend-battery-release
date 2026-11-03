#import <Foundation/Foundation.h>
// Ordered accepted source events from a single journal snapshot. Native dates
// only; epoch events invalidate active continuity. No wall/uptime clock mixing.
NSDictionary *IEBNativePowerWindow(NSArray *events, NSError **error);
