#import <Foundation/Foundation.h>
// Presentation-only query; input rows remain intact for next-sample CPU deltas.
NSArray<NSDictionary *> *IEBQueryProcesses(NSArray *rows, NSString *query, NSString *sortMode);
