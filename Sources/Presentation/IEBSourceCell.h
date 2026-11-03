#import <UIKit/UIKit.h>
@interface IEBSourceCell : UITableViewCell
@property(nonatomic, readonly) UILabel *nameLabel, *percentLabel, *timesLabel;
@property(nonatomic, readonly) UIImageView *sourceIcon;
- (void)configureName:(NSString *)name
           percentage:(NSString *)percentage
              details:(NSString *)details
                 icon:(UIImage *)icon;
@end
