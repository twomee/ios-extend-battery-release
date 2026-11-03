#import <Foundation/Foundation.h>
// Explicit allowlist: no application/process identities, PIDs, paths, raw errors or absolute dates.
NSData *IEBDiagnosticReport(NSDictionary *model, NSDictionary *snapshot, NSError **error);
NSString *IEBReadableDiagnosticReport(NSDictionary *model, NSDictionary *snapshot);

// Explicit language selection keeps report text deterministic without UIKit.
NSString *IEBReadableDiagnosticReportInLanguage(NSDictionary *model, NSDictionary *snapshot,
                                                NSString *language);
