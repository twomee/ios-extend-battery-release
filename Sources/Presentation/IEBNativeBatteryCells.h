#import <UIKit/UIKit.h>
BOOL IEBNativeTimeUsageSupported(void);
BOOL IEBApplyNativeTimeUsage(UITableViewCell *cell, id screenOn, id screenOff);
void IEBRefreshNativeTimeUsage(UITableViewCell *cell);
void IEBRestoreNativeTimeUsage(UITableViewCell *cell);
UIViewController *IEBOriginalChartController(UITableViewCell *cell);
BOOL IEBAttachNativeChart(UITableViewCell *cell, UIView *replacement);
void IEBLayoutNativeChart(UITableViewCell *cell);
void IEBRestoreNativeChart(UITableViewCell *cell);

BOOL IEBNativeTimeUsageIsActive(UITableViewCell *cell);

void IEBRestoreNativeChartView(UIView *replacement);

Class IEBNativeCellClassAtPath(id source, NSIndexPath *path);
