#import "IEBPowerObserver.h"
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <sys/sysctl.h>

@interface IEBPowerObserver () {
    void *_library;
    CFTypeRef (*_copyInfo)(void);
    CFArrayRef (*_copyList)(CFTypeRef);
    CFDictionaryRef (*_description)(CFTypeRef, CFTypeRef);
    CFRunLoopSourceRef _source;
    CFRunLoopTimerRef _timer;
    CFRunLoopRef _runLoop;
    mach_timebase_info_data_t _timebase;
    double _lastUptime;
    BOOL _sampled;
}
@property(nonatomic, readwrite) IEBSessionState *state;
@property(nonatomic, copy) NSString *bootID;
@property(nonatomic, copy) void (^handler)(IEBSessionState *, NSError *);
- (BOOL)sample:(NSError **)error;
- (void)deliver;
@end
static NSError *ObserverError(NSString *reason) {
    return [NSError errorWithDomain:@"IEBPowerObserver"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : reason}];
}
static void Changed(void *context) { [(__bridge IEBPowerObserver *)context deliver]; }
static void Heartbeat(CFRunLoopTimerRef timer, void *context) {
    (void)timer;
    Changed(context);
}
@implementation IEBPowerObserver
- (instancetype)initWithState:(IEBSessionState *)state
                      handler:(void (^)(IEBSessionState *, NSError *))handler {
    self = [super init];
    if (self) {
        _state = state ?: [IEBSessionState new];
        _handler = [handler copy];
    }
    return self;
}
- (IEBExternalPower)readPower {
    CFTypeRef info = _copyInfo();
    CFArrayRef list = info ? _copyList(info) : NULL;
    IEBExternalPower power = IEBExternalPowerUnknown;
    NSUInteger batteries = 0;
    if (list && CFGetTypeID(list) == CFArrayGetTypeID()) {
        for (id source in (__bridge NSArray *)list) {
            CFDictionaryRef raw = _description(info, (__bridge CFTypeRef)source);
            if (!raw || CFGetTypeID(raw) != CFDictionaryGetTypeID())
                continue;
            NSDictionary *row = (__bridge NSDictionary *)raw;
            if (![row[@"Type"] isEqual:@"InternalBattery"])
                continue;
            batteries++;
            id value = row[@"Power Source State"];
            power = [value isEqual:@"AC Power"]        ? IEBExternalPowerAttached
                    : [value isEqual:@"Battery Power"] ? IEBExternalPowerDetached
                                                       : IEBExternalPowerUnknown;
        }
    }
    if (list)
        CFRelease(list);
    if (info)
        CFRelease(info);
    return batteries == 1 ? power : IEBExternalPowerUnknown;
}
- (BOOL)sample:(NSError **)error {
    @autoreleasepool {
        IEBExternalPower power = [self readPower];
        double uptime =
            (double)mach_continuous_time() * (double)_timebase.numer / (double)_timebase.denom / 1e9;
        double wall = NSDate.date.timeIntervalSince1970;
        BOOL continuous = _sampled && uptime >= _lastUptime && uptime - _lastUptime <= 65;
        IEBSessionState *next = [self.state observingPower:power
                                                  wallTime:wall
                                                    uptime:uptime
                                                    bootID:self.bootID
                                                continuous:continuous
                                                     error:error];
        if (!next)
            return NO;
        self.state = next;
        _lastUptime = uptime;
        _sampled = YES;
        if (self.handler)
            self.handler(next, nil);
        return YES;
    }
}
- (void)deliver {
    NSError *error = nil;
    if (![self sample:&error]) {
        [self stop];
        if (self.handler)
            self.handler(nil, error);
    }
}
- (BOOL)start:(NSError **)error {
    if (error)
        *error = nil;
    if (_source) {
        if (error)
            *error = ObserverError(@"Observer already started");
        return NO;
    }
    char boot[129] = {0};
    size_t length = sizeof(boot) - 1;
    if (sysctlbyname("kern.bootsessionuuid", boot, &length, NULL, 0) != 0 || length == 0 ||
        mach_timebase_info(&_timebase) != KERN_SUCCESS || _timebase.denom == 0) {
        if (error)
            *error = ObserverError(@"Boot identity or continuous clock unavailable");
        return NO;
    }
    self.bootID = [NSString stringWithUTF8String:boot];
    _library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (_library) {
        _copyInfo = dlsym(_library, "IOPSCopyPowerSourcesInfo");
        _copyList = dlsym(_library, "IOPSCopyPowerSourcesList");
        _description = dlsym(_library, "IOPSGetPowerSourceDescription");
    }
    CFRunLoopSourceRef (*create)(void (*)(void *), void *) =
        _library ? dlsym(_library, "IOPSNotificationCreateRunLoopSource") : NULL;
    if (!_copyInfo || !_copyList || !_description || !create || !self.bootID) {
        [self stop];
        if (error)
            *error = ObserverError(@"Power notification API unavailable");
        return NO;
    }
    _source = create(Changed, (__bridge void *)self);
    if (!_source) {
        [self stop];
        if (error)
            *error = ObserverError(@"Power notification registration failed");
        return NO;
    }
    _runLoop = CFRunLoopGetCurrent();
    CFRetain(_runLoop);
    // Register first to avoid losing an edge between initial sample and subscription.
    CFRunLoopAddSource(_runLoop, _source, kCFRunLoopDefaultMode);
    CFRunLoopTimerContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    _timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 30, 30, 0, 0, Heartbeat, &context);
    if (!_timer) {
        [self stop];
        if (error)
            *error = ObserverError(@"Heartbeat creation failed");
        return NO;
    }
    CFRunLoopAddTimer(_runLoop, _timer, kCFRunLoopDefaultMode);
    _sampled = NO;
    if (![self sample:error]) {
        [self stop];
        return NO;
    }
    return YES;
}
- (void)stop {
    if (_timer) {
        CFRunLoopTimerInvalidate(_timer);
        CFRelease(_timer);
        _timer = NULL;
    }
    if (_source) {
        CFRunLoopSourceInvalidate(_source);
        CFRelease(_source);
        _source = NULL;
    }
    if (_runLoop) {
        CFRelease(_runLoop);
        _runLoop = NULL;
    }
    if (_library) {
        dlclose(_library);
        _library = NULL;
    }
    _sampled = NO;
}
- (void)dealloc {
    [self stop];
}
@end
