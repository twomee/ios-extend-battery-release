#import "IEBSessionStore.h"
#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static void Failure(NSError **error, NSString *reason) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBSessionStore"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : reason}];
}
static BOOL PrivateRegular(struct stat sb) {
    return S_ISREG(sb.st_mode) && sb.st_uid == getuid() && (sb.st_mode & 0777) == 0600 && sb.st_nlink == 1;
}
static int OpenDirectory(NSString *directory, NSError **error) {
    if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath ||
        [directory rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) {
        Failure(error, @"Invalid session directory");
        return -1;
    }
    int fd = open(directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat sb;
    if (fd < 0) {
        Failure(error, @"Cannot open session directory");
        return -1;
    }
    if (fstat(fd, &sb) != 0 || sb.st_uid != getuid() || (sb.st_mode & 0777) != 0700) {
        close(fd);
        Failure(error, @"Session directory must be private and owned by this user");
        return -1;
    }
    return fd;
}
BOOL IEBValidateSessionDirectory(NSString *directory, NSError **error) {
    if (error)
        *error = nil;
    int fd = OpenDirectory(directory, error);
    if (fd < 0)
        return NO;
    close(fd);
    return YES;
}
IEBSessionState *IEBLoadSession(NSString *directory, NSError **error) {
    if (error)
        *error = nil;
    int dir = OpenDirectory(directory, error);
    if (dir < 0)
        return nil;
    int fd = openat(dir, "session.plist", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    int saved = errno;
    close(dir);
    if (fd < 0) {
        if (saved != ENOENT)
            Failure(error, @"Cannot read session snapshot");
        return nil;
    }
    struct stat sb;
    if (fstat(fd, &sb) != 0 || !PrivateRegular(sb) || sb.st_size <= 0 || sb.st_size > 65536) {
        close(fd);
        Failure(error, @"Unsafe or oversized session snapshot");
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)sb.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t n = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            close(fd);
            Failure(error, @"Incomplete session snapshot read");
            return nil;
        }
        offset += (NSUInteger)n;
    }
    char extra;
    ssize_t n;
    do {
        n = read(fd, &extra, 1);
    } while (n < 0 && errno == EINTR);
    close(fd);
    if (n != 0) {
        Failure(error, @"Session snapshot changed during read");
        return nil;
    }
    id value = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:error];
    return value ? [IEBSessionState restoreSnapshot:value error:error] : nil;
}
BOOL IEBSaveSession(IEBSessionState *state, NSString *directory, NSError **error) {
    if (error)
        *error = nil;
    if (![state isKindOfClass:IEBSessionState.class]) {
        Failure(error, @"Invalid session state");
        return NO;
    }
    NSDictionary *snapshot = state.snapshot;
    if (![IEBSessionState restoreSnapshot:snapshot error:error])
        return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data || data.length > 65536) {
        if (data)
            Failure(error, @"Session snapshot too large");
        return NO;
    }
    int dir = OpenDirectory(directory, error);
    if (dir < 0)
        return NO;
    struct stat sb;
    if (fstatat(dir, "session.plist", &sb, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!PrivateRegular(sb)) {
            close(dir);
            Failure(error, @"Unsafe existing session snapshot");
            return NO;
        }
    } else if (errno != ENOENT) {
        close(dir);
        Failure(error, @"Cannot inspect session snapshot");
        return NO;
    }
    NSString *temp = [@".session-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int fd = openat(dir, temp.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) {
        close(dir);
        Failure(error, @"Cannot create temporary session snapshot");
        return NO;
    }
    NSUInteger offset = 0;
    BOOL ok = fchmod(fd, 0600) == 0;
    while (ok && offset < data.length) {
        ssize_t n = write(fd, (const char *)data.bytes + offset, data.length - offset);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            ok = NO;
            break;
        }
        offset += (NSUInteger)n;
    }
    if (ok && fsync(fd) != 0)
        ok = NO;
    if (close(fd) != 0)
        ok = NO;
    if (ok && renameat(dir, temp.UTF8String, dir, "session.plist") != 0)
        ok = NO;
    if (ok && fsync(dir) != 0)
        ok = NO;
    // After rename a directory-sync failure is reported even though the new file may exist.
    if (!ok) {
        unlinkat(dir, temp.UTF8String, 0);
        Failure(error, @"Could not durably replace session snapshot");
    }
    close(dir);
    return ok;
}
