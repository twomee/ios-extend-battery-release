#import "IEBCollectorBootstrap.h"
#import <string.h>
BOOL IEBIsCollectorFrameworkImage(const char *path) {
    if (!path)
        return NO;
    const char *slash = strrchr(path, '/');
    const char *name = slash ? slash + 1 : path;
    return strcmp(name, "PowerlogHelperdOperators") == 0 || strcmp(name, "PowerlogLiteOperators") == 0 ||
           strcmp(name, "PowerlogCore") == 0;
}
@interface IEBCollectorBootstrap ()
@property(copy) BOOL (^readiness)(void);
@property(copy) void (^start)(void);
@property BOOL started;
@end
@implementation IEBCollectorBootstrap
- (instancetype)initWithReadiness:(BOOL (^)(void))readiness start:(void (^)(void))start {
    NSParameterAssert(readiness);
    NSParameterAssert(start);
    self = [super init];
    if (self) {
        _readiness = [readiness copy];
        _start = [start copy];
    }
    return self;
}
- (void)attempt {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self attempt];
        });
        return;
    }
    if (self.started || !self.readiness())
        return;
    // Irreversible hook setup may re-enter: publish the committed state first.
    self.started = YES;
    self.start();
}
@end
