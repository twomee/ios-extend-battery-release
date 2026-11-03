#import "IEBCaptureSnapshot.h"
#import "../Session/IEBSessionStore.h"
#import "IEBNativeJournal.h"
#import <errno.h>
#import <fcntl.h>
#import <math.h>
#import <signal.h>
#import <sys/stat.h>
#import <unistd.h>
static id Fail(NSError **error, NSString *message) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBCaptureSnapshot"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    return nil;
}
static BOOL Number(id n) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n) != CFBooleanGetTypeID() &&
           isfinite([n doubleValue]);
}
static NSDictionary *Status(NSString *directory, NSError **error) {
    if (!IEBValidateSessionDirectory(directory, error))
        return nil;
    NSString *path = [directory stringByAppendingPathComponent:@"native-status.plist"];
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0)
        return Fail(error, @"Native writer status unavailable");
    struct stat sb;
    if (fstat(fd, &sb) != 0 || !S_ISREG(sb.st_mode) || sb.st_uid != getuid() || sb.st_nlink != 1 ||
        (sb.st_mode & 0777) != 0600 || sb.st_size <= 0 || sb.st_size > 8192) {
        close(fd);
        return Fail(error, @"Unsafe native writer status");
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)sb.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t n = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            close(fd);
            return Fail(error, @"Cannot read native writer status");
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
        return Fail(error, @"Native writer status changed during read");
    id raw = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListImmutable
                                                        format:NULL
                                                         error:error];
    if (![raw isKindOfClass:NSDictionary.class] || [raw count] != 8)
        return Fail(error, @"Invalid native writer status shape");
    NSDictionary *s = raw;
    if (![@[
            @"none", @"status-store", @"queue-overflow", @"private-directory", @"journal-init",
            @"native-clock", @"journal-checkpoint", @"journal-write", @"native-power", @"native-activity"
        ] containsObject:s[@"failure_reason"]])
        return Fail(error, @"Unknown native writer failure reason");
    if (!Number(s[@"version"]) || ![s[@"version"] isEqual:@1] || !Number(s[@"writer_pid"]) ||
        [s[@"writer_pid"] doubleValue] < 1 || [s[@"writer_pid"] doubleValue] > INT_MAX ||
        [s[@"writer_pid"] doubleValue] != floor([s[@"writer_pid"] doubleValue]) ||
        !Number(s[@"observed_wall_time"]) || [s[@"observed_wall_time"] doubleValue] <= 0 ||
        !Number(s[@"error_count"]) || [s[@"error_count"] doubleValue] < 0 ||
        [s[@"error_count"] doubleValue] > 9007199254740991.0 ||
        [s[@"error_count"] doubleValue] != floor([s[@"error_count"] doubleValue]) ||
        ![s[@"writer_epoch"] isKindOfClass:NSString.class] || ![s[@"writer_epoch"] length] ||
        [s[@"writer_epoch"] length] > 128)
        return Fail(error, @"Invalid native writer status metadata");
    for (NSString *key in @[ @"failed", @"feature_ready" ]) {
        id flag = s[key];
        if (![flag isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)flag) != CFBooleanGetTypeID())
            return Fail(error, @"Invalid native writer status flag");
    }
    if ([s[@"feature_ready"] boolValue])
        return Fail(error, @"Source candidate cannot certify feature readiness");
    return s;
}
static NSDictionary *Capture(NSString *directory, double start, double end, NSError **error) {
    if (error)
        *error = nil;
    NSDictionary *status = Status(directory, error);
    if (!status)
        return nil;
    NSDictionary *journal = start || end ? IEBReadNativeJournalSelection(directory, start, end, error)
                                         : IEBReadNativeJournal(directory, error);
    if (!journal)
        return nil;
    double age = NSDate.date.timeIntervalSince1970 - [status[@"observed_wall_time"] doubleValue];
    BOOL current = [status[@"writer_epoch"] isEqual:journal[@"writer_epoch"]] &&
                   [status[@"writer_pid"] isEqual:journal[@"writer_pid"]] && age >= 0 && age <= 65 &&
                   kill([status[@"writer_pid"] intValue], 0) == 0;
    BOOL failed = [journal[@"source_failed"] boolValue] || [status[@"failed"] boolValue] || !current;
    NSMutableDictionary *result = [journal mutableCopy];
    result[@"writer_current"] = @(current);
    result[@"source_healthy"] = @(!failed);
    result[@"failure_reason"] = status[@"failure_reason"];
    result[@"source_failed"] = @(failed);
    if (failed && !journal[@"window"][@"end"]) {
        NSMutableDictionary *window = [journal[@"window"] mutableCopy];
        window[@"power_complete"] = @NO;
        result[@"window"] = window;
    }
    return [result copy];
}

NSDictionary *IEBReadCaptureSnapshot(NSString *directory, NSError **error) {
    return Capture(directory, 0, 0, error);
}
NSDictionary *IEBReadCaptureSelection(NSString *directory, double start, double end, NSError **error) {
    if (start == 0 && end == 0) {
        Fail(error, @"Invalid empty capture selection");
        return nil;
    }
    return Capture(directory, start, end, error);
}
