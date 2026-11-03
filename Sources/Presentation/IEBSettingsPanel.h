#import "IEBStatisticsController.h"
BOOL IEBShowSettingsPanel(UIViewController *owner, UISegmentedControl *segment,
                          IEBStatisticsController *statistics, void (^selectRange)(NSInteger));
void IEBLayoutSettingsPanel(UIViewController *owner);
void IEBDismissSettingsPanel(UIViewController *owner);
BOOL IEBHasSettingsPanel(UIViewController *owner);

void IEBRebindSettingsPanel(UIViewController *owner, UISegmentedControl *segment);

BOOL IEBSelectNativeRange(UIViewController *owner, UISegmentedControl *control, id specifier, BOOL reversed,
                          NSInteger range);

void IEBRememberSettingsRange(UIViewController *owner, NSInteger range);
void IEBSyncSettingsRange(UIViewController *owner, UISegmentedControl *control);
