#import <Foundation/Foundation.h>
// Aggregate-only private records. Missing measurements remain NSNull.
NSDictionary *IEBSummarizeClosedCycle(NSDictionary *capture, NSError **error);
// Deltas are a minus b. Relative rate is (rateA/rateB - 1)*100 with positive B,
// and both cycles >=60s (product eligibility rule, not a sampling guarantee).
// Never battery percentage lost or Wh; unavailable/invalid comparisons remain NSNull.
NSDictionary *IEBCompareCycleSummaries(NSDictionary *a, NSDictionary *b);
NSArray<NSDictionary *> *IEBReadNativeCycleHistory(NSString *directory, NSError **error);
// Enrich only a selected saved cycle; unavailable/expired energy preserves its summary.
NSDictionary *IEBLoadHistoricalCycle(NSDictionary *record, NSString *database, NSError **error);
