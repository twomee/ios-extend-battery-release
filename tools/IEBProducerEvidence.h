#import <Foundation/Foundation.h>

// A marker inside known request configurations opts into aggregate-only evidence.
BOOL IEBIsProducerProbe(id configuration);
NSDictionary *IEBProducerEvidence(id rawResponse, id configuration);
// Client-side allowlist: never forward arbitrary dictionaries returned by a daemon.
NSDictionary *IEBSanitizeProducerEvidence(id evidence);
