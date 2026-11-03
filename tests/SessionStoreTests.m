#import "../Sources/Session/IEBSessionStore.h"
#import <sys/stat.h>
#import <unistd.h>
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Store FAIL %d: %s\n", __LINE__, #c);                                            \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static IEBSessionState *Observe(IEBSessionState *state, IEBExternalPower p, double t) {
    return [state observingPower:p wallTime:1000 + t uptime:t bootID:@"boot" continuous:YES error:NULL];
}
int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        REQUIRE([fm createDirectoryAtPath:dir
              withIntermediateDirectories:NO
                               attributes:@{
                                   NSFilePosixPermissions : @0700
                               }
                                    error:NULL]);
        NSError *error = nil;
        REQUIRE(!IEBLoadSession(dir, &error) && !error);
        IEBSessionState *state = Observe(Observe([IEBSessionState new], IEBExternalPowerAttached, 10),
                                         IEBExternalPowerDetached, 20);
        REQUIRE(IEBSaveSession(state, dir, &error) && !error);
        IEBSessionState *loaded = IEBLoadSession(dir, &error);
        REQUIRE(loaded && !error && !loaded.complete && loaded.end.timeIntervalSince1970 == 1020);
        IEBSessionState *frozen = Observe(state, IEBExternalPowerAttached, 30);
        REQUIRE(IEBSaveSession(frozen, dir, &error));
        REQUIRE([IEBLoadSession(dir, &error).snapshot isEqual:frozen.snapshot] && !error);
        mode_t previousMask = umask(0777);
        BOOL saved = IEBSaveSession(frozen, dir, &error);
        umask(previousMask);
        REQUIRE(saved && IEBLoadSession(dir, &error) && !error);
        NSString *file = [dir stringByAppendingPathComponent:@"session.plist"];
        struct stat sb;
        REQUIRE(lstat(file.fileSystemRepresentation, &sb) == 0 && (sb.st_mode & 0777) == 0600);
        REQUIRE([@"broken" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL]);
        REQUIRE(!IEBLoadSession(dir, &error) && error);
        REQUIRE([[NSMutableData dataWithLength:65537] writeToFile:file atomically:NO]);
        REQUIRE(!IEBLoadSession(dir, &error) && error);
        REQUIRE([fm removeItemAtPath:file error:NULL]);
        NSString *outside = [dir stringByAppendingPathComponent:@"outside"];
        REQUIRE([@"preserve" writeToFile:outside atomically:NO encoding:NSUTF8StringEncoding error:NULL]);
        REQUIRE(symlink(outside.fileSystemRepresentation, file.fileSystemRepresentation) == 0);
        REQUIRE(!IEBLoadSession(dir, &error) && error);
        REQUIRE(!IEBSaveSession(frozen, dir, &error) && error);
        REQUIRE([[NSString stringWithContentsOfFile:outside encoding:NSUTF8StringEncoding
                                              error:NULL] isEqual:@"preserve"]);
        REQUIRE(chmod(dir.fileSystemRepresentation, 0755) == 0);
        REQUIRE(!IEBLoadSession(dir, &error) && error);
        REQUIRE(!IEBSaveSession(frozen, dir, &error) && error);
        REQUIRE(chmod(dir.fileSystemRepresentation, 0700) == 0);
        NSString *alias = [dir stringByAppendingString:@"-alias"];
        REQUIRE(symlink(dir.fileSystemRepresentation, alias.fileSystemRepresentation) == 0);
        REQUIRE(!IEBLoadSession(alias, &error) && error);
        REQUIRE(!IEBSaveSession(frozen, alias, &error) && error);
        REQUIRE(unlink(alias.fileSystemRepresentation) == 0);
        REQUIRE(!IEBSaveSession(nil, dir, &error) && error);
        REQUIRE(!IEBLoadSession(@"relative", &error) && error);
        REQUIRE([fm removeItemAtPath:dir error:NULL]);
        REQUIRE(!IEBSaveSession(frozen, dir, &error) && error);
        puts("PASS atomic session store, private modes, invalid snapshots and restart recovery");
        return 0;
    }
}
