#import "../Sources/Compatibility/IEBPlatformSupport.h"
#import "IEBCompatibilityEvidence.h"
#import <TargetConditionals.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

// Powerlog initializers may terminate an unentitled process. Isolate that failure.
static int IsolatedCollector(void) {
    char executable[PATH_MAX];
    uint32_t capacity = sizeof(executable);
    int childExit = -1, childSignal = 0;
    NSData *output = nil;
    NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ieb-metadata-XXXXXX"];
    char *pattern = strdup(temporary.fileSystemRepresentation);
    int fd = pattern ? mkstemp(pattern) : -1;
    BOOL anonymous = fd >= 0 && unlink(pattern) == 0;
    int launchError = anonymous ? 0 : errno;
    NSString *failureStage = @"temporary_storage";
    free(pattern);
    BOOL executableKnown = anonymous && _NSGetExecutablePath(executable, &capacity) == 0;
    if (anonymous && !executableKnown)
        failureStage = @"executable_path";
    if (executableKnown) {
        failureStage = @"spawn";
        posix_spawn_file_actions_t actions;
        int setup = posix_spawn_file_actions_init(&actions);
        BOOL initialized = setup == 0;
        if (!setup)
            setup = posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO);
        if (!setup)
            setup = posix_spawn_file_actions_addclose(&actions, fd);
        if (!setup)
            setup = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
        char *arguments[] = {executable, "_collector-child", NULL};
        extern char **environ;
        pid_t pid = 0;
#ifdef IEB_COMPATIBILITY_TEST_SPAWN_ERROR
        (void)arguments;
        (void)environ;
        (void)setup;
        int spawned = EPERM;
#else
        int spawned = setup ? setup : posix_spawn(&pid, executable, &actions, NULL, arguments, environ);
#endif
        if (initialized)
            posix_spawn_file_actions_destroy(&actions);
        launchError = spawned;
        if (!spawned) {
            failureStage = @"child_execution";
            int status = 0;
            BOOL finished = NO;
#ifdef IEB_COMPATIBILITY_TEST_TIMEOUT
            const NSUInteger attempts = 2;
#else
            const NSUInteger attempts = 2500;
#endif
            for (NSUInteger attempt = 0; attempt < attempts; attempt++) {
                pid_t waited = waitpid(pid, &status, WNOHANG);
                if (waited == pid) {
                    finished = YES;
                    break;
                }
                if (waited < 0 && errno != EINTR) {
                    finished = YES;
                    status = -1;
                    break;
                }
                usleep(10000);
            }
            if (!finished) {
                kill(pid, SIGKILL);
                while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
                }
            }
            if (status >= 0) {
                if (WIFEXITED(status))
                    childExit = WEXITSTATUS(status);
                if (WIFSIGNALED(status))
                    childSignal = WTERMSIG(status);
            }
            struct stat info;
            if (fstat(fd, &info) == 0 && info.st_size > 0 && info.st_size <= 65536 &&
                lseek(fd, 0, SEEK_SET) >= 0) {
                NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
                NSUInteger received = 0;
                while (received < data.length) {
                    ssize_t n = read(fd, (char *)data.mutableBytes + received, data.length - received);
                    if (n < 0 && errno == EINTR)
                        continue;
                    if (n <= 0)
                        break;
                    received += (NSUInteger)n;
                }
                if (received == data.length)
                    output = data;
            }
        }
    }
    if (fd >= 0)
        close(fd);
    id decoded = output ? [NSJSONSerialization JSONObjectWithData:output options:0 error:NULL] : nil;
    if (childExit >= 20 && childExit <= 23 && [decoded isKindOfClass:NSDictionary.class] &&
        [decoded[@"scope"] isEqual:@"collector"] && [decoded[@"summary"] isKindOfClass:NSDictionary.class]) {
        if (fwrite(output.bytes, 1, output.length, stdout) != output.length)
            return 74;
        return childExit;
    }
    NSOperatingSystemVersion runtime = NSProcessInfo.processInfo.operatingSystemVersion;
#if TARGET_OS_SIMULATOR
    NSString *environment = @"simulator";
#elif TARGET_OS_IPHONE
    NSString *environment = @"device";
#else
    NSString *environment = @"host";
#endif
    NSDictionary *failure = @{
        @"schema_version" : @1,
        @"scope" : @"collector",
        @"context" : @"standalone",
        @"environment" : environment,
        @"os_version" : [NSString stringWithFormat:@"%ld.%ld.%ld", (long)runtime.majorVersion,
                                                   (long)runtime.minorVersion, (long)runtime.patchVersion],
        @"os_build" : NSNull.null,
        @"summary" : @{@"status" : @"environment_unavailable"},
        @"inspection_completed" : @NO,
        @"failure_stage" : failureStage,
        @"launch_error" : launchError ? @(launchError) : (id)NSNull.null,
        @"child_exit_code" : childExit >= 0 ? @(childExit) : (id)NSNull.null,
        @"child_signal" : childSignal ? @(childSignal) : (id)NSNull.null,
        @"observations" : NSNull.null,
        @"images" : NSNull.null,
        @"target_methods_invoked" : @NO,
        @"history_queried" : @NO,
        @"hooks_installed" : @NO,
        @"limitations" : @"Framework initialization did not produce metadata in this standalone process; no "
                         @"support conclusion is possible."
    };
    NSData *json =
        [NSJSONSerialization dataWithJSONObject:failure
                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                          error:NULL];
    if (!json || fwrite(json.bytes, 1, json.length, stdout) != json.length || puts("") == EOF)
        return 74;
    return 20;
}

// Inspect metadata only: no controller creation, hooks or private selector invocation.
static NSArray *Specs(BOOL settings) {
    NSString *chart = @"_TtC14BatteryUsageUI24PLBUIChartViewController", *time = @"PLBatteryUITimeUsageCell";
    if (settings)
        return @[
            @[ @"method", @"UIViewController", @"viewDidLoad", @"v16@0:8" ],
            @[ @"method", @"PSSpecifier", @"setValues:titles:", @"v32@0:8@16@24" ],
            @[ @"method", @"BatteryUIController", @"setBatteryUIQueryRange:specifier:", @"v32@0:8@16@24" ],
            @[ @"method", @"PLBatteryUISegmentCell", @"refreshCellContentsWithSpecifier:", @"v24@0:8@16" ],
            @[ @"method", chart, @"setDataset:endOfDay:", @"v32@0:8@16@24" ],
            @[ @"method", chart, @"setMarginWithTop:bottom:", @"v32@0:8d16d24" ],
            @[ @"method", chart, @"setContainerBackgroundColor:", @"v24@0:8@16" ],
            @[ @"method", @"PLBatteryUIGraphViewTableCell", @"layoutSubviews", @"v16@0:8" ],
            @[ @"method", time, @"refreshCellContentsWithSpecifier:", @"v24@0:8@16" ],
            @[ @"method", time, @"handleGesture:", @"v24@0:8@16" ],
            @[ @"method", time, @"getLoczlizedHourMinuteStringFromSeconds:", @"@24@0:8d16" ],
            @[ @"ivar", time, @"_screenOnTimeText", @"present" ],
            @[ @"ivar", time, @"_screenOffTimeText", @"present" ]
        ];
    return @[
        @[ @"method", @"NSObject", @"description", @"@16@0:8" ],
        @[ @"method", @"PLAppTimeService", @"handleBatteryCallback:", @"v24@0:8@16" ],
        @[
            @"method", @"PLAppTimeService",
            @"logProportionateAggregateEntry:withStartDate:withEndDate:", @"v40@0:8@16@24@32"
        ],
        @[ @"method", @"PLEntry", @"entryDate", @"@16@0:8" ],
        @[ @"method", @"PLEntry", @"objectForKeyedSubscript:", @"@24@0:8@16" ],
        @[ @"class_method", @"NSDate", @"monotonicDate", @"@16@0:8" ]
    ];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || (strcmp(argv[1], "settings") && strcmp(argv[1], "collector") &&
                          strcmp(argv[1], "_collector-child"))) {
            fputs("usage: ieb-compatibility-probe settings|collector\n", stderr);
            return 64;
        }
        if (!strcmp(argv[1], "collector"))
            return IsolatedCollector();
#ifdef IEB_COMPATIBILITY_TEST_CHILD
        if (strcmp(argv[1], "settings")) {
#ifdef IEB_COMPATIBILITY_TEST_TIMEOUT
            usleep(1000000);
#endif
            _exit(1);
        }
#endif
        alarm(20); // Bound framework loading; the default SIGALRM terminates this diagnostic only.
        @try {
            BOOL settings = !strcmp(argv[1], "settings");
            NSMutableArray *paths = [NSMutableArray
                arrayWithObject:@"/System/Library/Frameworks/Foundation.framework/Foundation"];
            [paths addObjectsFromArray:settings ? @[
                @"/System/Library/Frameworks/UIKit.framework/UIKit",
                @"/System/Library/PrivateFrameworks/Preferences.framework/Preferences",
                @"/System/Library/PreferenceBundles/BatteryUsageUI.bundle/BatteryUsageUI"] : @[
                @"/System/Library/PrivateFrameworks/PowerlogCore.framework/PowerlogCore",
                @"/System/Library/PrivateFrameworks/PowerlogHelperdOperators.framework/PowerlogHelperdOperators"]];
            NSMutableArray *images = [NSMutableArray new], *observations = [NSMutableArray new];
            BOOL loaded = YES;
            for (NSString *path in paths) {
                BOOL ok = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL) != NULL;
                loaded = loaded && ok;
                [images addObject:@{@"image" : path.lastPathComponent, @"loaded" : @(ok)}];
            }
            NSArray *specs = Specs(settings);
            for (NSArray *spec in specs)
                [observations addObject:IEBInspectCompatibilityMember(spec)];
            NSDictionary *summary = IEBCompatibilitySummary(observations, specs.count, loaded);
            NSDictionary *version = [NSDictionary
                dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
#if TARGET_OS_SIMULATOR
            NSString *environment = @"simulator";
            NSOperatingSystemVersion runtime = NSProcessInfo.processInfo.operatingSystemVersion;
            version = @{
                @"ProductVersion" :
                    [NSString stringWithFormat:@"%ld.%ld.%ld", (long)runtime.majorVersion,
                                               (long)runtime.minorVersion, (long)runtime.patchVersion]
            };
#elif TARGET_OS_IPHONE
            NSString *environment = @"device";
#else
            NSString *environment = @"host";
#endif
            NSDictionary *report = @{
                @"schema_version" : @1,
                @"inspection_completed" : @YES,
                @"scope" : settings ? @"settings" : @"collector",
                @"context" : @"standalone",
                @"environment" : environment,
                @"os_version" : version[@"ProductVersion"] ?: (id)NSNull.null,
                @"os_build" : version[@"ProductBuildVersion"] ?: (id)NSNull.null,
                @"shipping_gate_accepts_version" :
                    @(IEBPlatformIsSupported(version[@"ProductVersion"], version[@"ProductBuildVersion"])),
                @"target_methods_invoked" : @NO,
                @"history_queried" : @NO,
                @"hooks_installed" : @NO,
                @"images" : images,
                @"observations" : observations,
                @"summary" : summary,
                @"limitations" : @"Metadata only. Standalone context does not verify injection, clocks, DB "
                                 @"schema, accounting or runtime support."
            };
            NSError *error = nil;
            NSData *json =
                [NSJSONSerialization dataWithJSONObject:report
                                                options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                  error:&error];
            if (!json) {
                fputs("compatibility report encoding failed\n", stderr);
                return 74;
            }
            if (fwrite(json.bytes, 1, json.length, stdout) != json.length || puts("") == EOF)
                return 74;
            NSString *status = summary[@"status"];
            return [status isEqual:@"metadata_match_only"] ? 22
                   : [status isEqual:@"abi_mismatch"]      ? 21
                   : [status isEqual:@"invalid"]           ? 23
                                                           : 20;
        } @catch (NSException *exception) {
            (void)exception;
            fputs("compatibility metadata inspection failed\n", stderr);
            return 23;
        }
    }
}
