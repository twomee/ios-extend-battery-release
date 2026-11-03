#import <Foundation/Foundation.h>
NSDictionary *IEBStatisticsModel(NSDictionary *capture, NSDictionary *energySource, NSError **error);
NSDictionary *IEBLoadStatistics(NSString *directory, NSString *database, double selectedStart,
                                double selectedEnd, NSError **error);
