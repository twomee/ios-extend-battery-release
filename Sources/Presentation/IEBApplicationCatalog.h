#import <UIKit/UIKit.h>
// Call on the controller's background loader queue. Never exports app identities.
NSDictionary *IEBLoadApplicationCatalog(NSArray<NSString *> *identities);
