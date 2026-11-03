#import <Foundation/Foundation.h>
// Internal on-device snapshot. Reconciles journal state with the current writer's health.
NSDictionary *IEBReadCaptureSnapshot(NSString *directory, NSError **error);

NSDictionary *IEBReadCaptureSelection(NSString *directory, double start, double end, NSError **error);
