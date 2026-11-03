#import "../Sources/Session/IEBSessionStore.h"
#import "../Sources/Statistics/IEBActivityEvidence.h"
#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <sys/stat.h>
#import <unistd.h>
int main(int argc, const char *argv[]) {
    (void)argv;
    @autoreleasepool {
        if (argc != 1)
            return 64;
        NSError *directoryError = nil;
        if (!IEBValidateSessionDirectory(@"/var/mobile/Library/IEBNativeCapture", &directoryError))
            return 20;
        int fd = open("/var/mobile/Library/IEBNativeCapture/activity-evidence.plist",
                      O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
        if (fd < 0) {
            fprintf(stderr, "Native activity evidence unavailable\n");
            return 20;
        }
        struct stat sb;
        if (fstat(fd, &sb) != 0 || !S_ISREG(sb.st_mode) || sb.st_uid != getuid() || sb.st_nlink != 1 ||
            (sb.st_mode & 0777) != 0600 || sb.st_size <= 0 || sb.st_size > 65536) {
            close(fd);
            return 23;
        }
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)sb.st_size];
        NSUInteger offset = 0;
        while (offset < data.length) {
            ssize_t n = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
            if (n < 0 && errno == EINTR)
                continue;
            if (n <= 0) {
                close(fd);
                return 23;
            }
            offset += (NSUInteger)n;
        }
        char extra;
        ssize_t n;
        do {
            n = read(fd, &extra, 1);
        } while (n < 0 && errno == EINTR);
        close(fd);
        if (n != 0)
            return 23;
        NSError *error = nil;
        id value = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListImmutable
                                                              format:NULL
                                                               error:&error];
        NSDictionary *safe = IEBSanitizeActivitySummary(value, &error);
        if (!safe || error) {
            fprintf(stderr, "Native activity evidence invalid\n");
            return 23;
        }
        pid_t writer = (pid_t)[safe[@"writer_pid"] intValue];
        if (!IEBActivitySummaryIsCurrent(safe, NSDate.date.timeIntervalSince1970, kill(writer, 0) == 0)) {
            fprintf(stderr, "Native activity evidence is stale or writer is unavailable\n");
            return 20;
        }
        NSData *json =
            [NSJSONSerialization dataWithJSONObject:safe
                                            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                              error:&error];
        if (!json)
            return 74;
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 22;
    }
}
