#import <Foundation/Foundation.h>

// Input rows are from one EnergyEstimateEvents table snapshot. Dates use the
// native monotonic clock; offsets are milliseconds. Returned units retain
// Apple's stored energy scale and per-record rounding, not physical accuracy.
NSDictionary *IEBEnergyForWindow(NSArray *rows, double start, double end, NSError **error);
