#import <UIKit/UIKit.h>
NSString *IEBProcessStatusText(NSDictionary *snapshot);
@interface IEBProcessesController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithLoader:(NSDictionary * (^)(void))loader;
@end
