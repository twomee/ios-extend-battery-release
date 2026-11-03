#import <Foundation/Foundation.h>

// Reports structure only; presence of data never proves exact time boundaries.
NSDictionary *IEBSummarizeResponse(id response);
NSString *IEBFeasibilityDecision(NSDictionary *reference, NSDictionary *scoped);

// Strict numeric input for one bounded read-only diagnostic window.
NSDictionary *IEBParseQueryWindow(NSString *start, NSString *end);
