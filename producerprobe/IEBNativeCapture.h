#import <Foundation/Foundation.h>
// Clock provider returns NSDate.monotonicDate in the already entitled native daemon.
void IEBStartNativeCapture(NSDate * (^clock)(void));
void IEBObserveNativePower(id connected, NSDate *date);
void IEBObserveNativeActivity(NSDictionary *entry, NSDate *start, NSDate *end);

void IEBObserveNativeActivityEntry(id entry, NSDate *start, NSDate *end);

#if IEB_NATIVE_CAPTURE_TESTING
void IEBStopNativeCaptureForTesting(void);
#endif
