#import <Foundation/Foundation.h>
NSArray<NSString *> *IEBActivityMetricKeys(void);
// Input may contain app identifiers; output contains only metrics and has_app.
// Nil without error means an unrelated aggregate. No zero/missing substitution.
NSDictionary *IEBActivityEvidence(NSDictionary *entry, NSDate *start, NSDate *end, NSError **error);

NSDictionary *IEBSanitizeActivitySummary(id summary, NSError **error);

BOOL IEBActivitySummaryIsCurrent(NSDictionary *summary, double now, BOOL writerExists);
