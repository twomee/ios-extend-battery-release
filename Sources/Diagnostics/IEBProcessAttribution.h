#import <Foundation/Foundation.h>
/// Unique exact process/executable matches only. Never infer energy from CPU.
NSDictionary *IEBProcessAttribution(NSArray *sources, NSDictionary *catalog, NSDictionary *snapshot,
                                    NSDictionary *previous);
