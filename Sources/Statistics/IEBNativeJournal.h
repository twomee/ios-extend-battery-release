#import <Foundation/Foundation.h>
// Single writer on its serial queue. All dates are Powerlog monotonic dates.
@interface IEBNativeJournal : NSObject
- (instancetype)initWithDirectory:(NSString *)directory
                            epoch:(NSString *)epoch
                       nativeTime:(double)time
                            error:(NSError **)error;
- (BOOL)markSourceFailed:(NSError **)error;
- (BOOL)recordPower:(NSInteger)power nativeTime:(double)time error:(NSError **)error;
- (BOOL)recordGapAtNativeTime:(double)time error:(NSError **)error;
- (BOOL)recordActivity:(NSDictionary *)entry start:(NSDate *)start end:(NSDate *)end error:(NSError **)error;
- (BOOL)checkpointAtNativeTime:(double)time error:(NSError **)error;
@end
// Internal statistics include app IDs for the on-device Settings adapter only.
// Diagnostic callers must discard apps and expose cardinality/aggregate values.
NSDictionary *IEBReadNativeJournal(NSString *directory, NSError **error);

NSDictionary *IEBReadNativeJournalSelection(NSString *directory, double start, double end, NSError **error);

NSArray<NSDictionary *> *IEBReadNativeCycleHistory(NSString *directory, NSError **error);
