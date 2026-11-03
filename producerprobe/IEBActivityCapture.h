#import <Foundation/Foundation.h>
void IEBStartActivityCapture(BOOL hookInstalled);
void IEBObserveActivityAggregate(id entry, NSDate *start, NSDate *end);

#if IEB_ACTIVITY_CAPTURE_TESTING
void IEBStopActivityCaptureForTesting(void);
#endif
