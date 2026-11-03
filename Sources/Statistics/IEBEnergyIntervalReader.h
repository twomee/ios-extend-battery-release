#import <Foundation/Foundation.h>

// Reads one consistent read-only database snapshot; never exports raw rows.
// Retention extrema are observations, not proof of continuous coverage.
NSDictionary *IEBReadEnergyIntervals(NSString *path, double start, double end, NSError **error);

NSDictionary *IEBReadEnergyAndLevels(NSString *path, double start, double end, NSError **error);
