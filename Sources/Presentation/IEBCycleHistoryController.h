#import <UIKit/UIKit.h>
@interface IEBCycleHistoryController : UITableViewController
- (instancetype)initWithListLoader:(NSArray<NSDictionary *> * (^)(NSError **))listLoader
                      detailLoader:(NSDictionary * (^)(NSDictionary *, NSError **))detailLoader;
@end
