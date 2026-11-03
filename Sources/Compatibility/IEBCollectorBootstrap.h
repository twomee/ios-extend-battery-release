#import <Foundation/Foundation.h>
BOOL IEBIsCollectorFrameworkImage(const char *path);
@interface IEBCollectorBootstrap : NSObject
- (instancetype)initWithReadiness:(BOOL (^)(void))readiness start:(void (^)(void))start;
- (void)attempt;
@end
