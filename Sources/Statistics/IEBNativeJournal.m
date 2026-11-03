#import "IEBNativeJournal.h"
#import "../Session/IEBNativePowerWindow.h"
#import "../Session/IEBSessionStore.h"
#import "IEBActivityEvidence.h"
#import "IEBCycleHistory.h"
#import <errno.h>
#import <fcntl.h>
#import <math.h>
#import <sqlite3.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>

static BOOL Fail(NSError **error, NSString *reason) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBNativeJournal"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : reason}];
    return NO;
}
static double Now(void) {
    struct timespec t;
    return clock_gettime(CLOCK_MONOTONIC, &t) == 0 ? t.tv_sec + t.tv_nsec / 1e9 : NAN;
}
static int Expired(void *context) {
    double now = Now();
    return !isfinite(now) || now > *(double *)context;
}
static BOOL Date(double t) { return isfinite(t) && t > 0; }
static BOOL SQL(sqlite3 *db, NSString *sql, NSArray *args, NSError **error) {
    sqlite3_stmt *stmt = NULL;
    BOOL ok = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK;
    if (ok)
        for (NSUInteger i = 0; i < args.count; i++) {
            id v = args[i];
            int rc;
            if (v == NSNull.null)
                rc = sqlite3_bind_null(stmt, (int)i + 1);
            else if ([v isKindOfClass:NSNumber.class])
                rc = sqlite3_bind_double(stmt, (int)i + 1, [v doubleValue]);
            else if ([v isKindOfClass:NSData.class])
                rc = sqlite3_bind_blob(stmt, (int)i + 1, [v bytes], (int)[v length], SQLITE_TRANSIENT);
            else if ([v isKindOfClass:NSString.class]) {
                NSData *d = [v dataUsingEncoding:NSUTF8StringEncoding];
                rc = sqlite3_bind_text(stmt, (int)i + 1, d.bytes, (int)d.length, SQLITE_TRANSIENT);
            } else
                rc = SQLITE_MISMATCH;
            if (rc != SQLITE_OK) {
                ok = NO;
                break;
            }
        }
    if (ok)
        ok = sqlite3_step(stmt) == SQLITE_DONE;
    if (stmt && sqlite3_finalize(stmt) != SQLITE_OK)
        ok = NO;
    return ok ? YES : Fail(error, @"Native journal database operation failed");
}
static int Lock(NSString *directory, NSError **error) {
    if (!IEBValidateSessionDirectory(directory, error))
        return -1;
    NSString *path = [directory stringByAppendingPathComponent:@"native-journal.lock"];
    int fd = open(path.fileSystemRepresentation,
                  O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
    if (fd >= 0) {
        if (fchmod(fd, 0600) != 0) {
            close(fd);
            Fail(error, @"Cannot secure journal lock");
            return -1;
        }
    } else if (errno == EEXIST)
        fd = open(path.fileSystemRepresentation, O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    struct stat sb;
    if (fd < 0 || fstat(fd, &sb) != 0 || !S_ISREG(sb.st_mode) || sb.st_uid != getuid() || sb.st_nlink != 1 ||
        (sb.st_mode & 0777) != 0600 || flock(fd, LOCK_EX | LOCK_NB) != 0) {
        if (fd >= 0)
            close(fd);
        Fail(error, @"Journal writer unavailable or already active");
        return -1;
    }
    return fd;
}
static sqlite3 *Open(NSString *directory, BOOL write, NSError **error) {
    if (!IEBValidateSessionDirectory(directory, error))
        return NULL;
    char *canonical = realpath(directory.fileSystemRepresentation, NULL);
    if (!canonical) {
        Fail(error, @"Cannot resolve journal directory");
        return NULL;
    }
    NSString *parent = [NSString stringWithUTF8String:canonical];
    free(canonical);
    NSString *path = [parent stringByAppendingPathComponent:@"native-journal.sqlite"];
    int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
    int fd = open(path.fileSystemRepresentation, flags);
    if (fd < 0 && write && errno == ENOENT) {
        fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd >= 0 && fchmod(fd, 0600) != 0) {
            close(fd);
            Fail(error, @"Cannot secure new native journal");
            return NULL;
        }
    }
    struct stat sb;
    if (fd < 0 || fstat(fd, &sb) != 0 || !S_ISREG(sb.st_mode) || sb.st_uid != getuid() || sb.st_nlink != 1 ||
        (sb.st_mode & 0777) != 0600) {
        if (fd >= 0)
            close(fd);
        Fail(error, @"Unsafe or unavailable native journal file");
        return NULL;
    }
    close(fd);
    sqlite3 *db = NULL;
    int sqliteFlags =
        (write ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &db, sqliteFlags, NULL) != SQLITE_OK) {
        if (db)
            sqlite3_close(db);
        Fail(error, @"Cannot open native journal");
        return NULL;
    }
    sqlite3_busy_timeout(db, 1000);
    return db;
}
static BOOL NumericColumn(sqlite3_stmt *s, int c) {
    int type = sqlite3_column_type(s, c);
    return (type == SQLITE_INTEGER || type == SQLITE_FLOAT) && isfinite(sqlite3_column_double(s, c));
}
static BOOL ValidBounds(sqlite3 *db, NSString *epoch, NSError **error) {
    sqlite3_stmt *s = NULL;
    const char *sql = "SELECT 1 FROM activities WHERE epoch=? AND (typeof(a) NOT IN ('integer','real') OR "
                      "typeof(b) NOT IN ('integer','real') OR NOT(a>0 AND b>a AND a<=1.7976931348623157e308 "
                      "AND b<=1.7976931348623157e308 AND b-a<=1.7976931348623157e308)) LIMIT 1";
    if (sqlite3_prepare_v2(db, sql, -1, &s, NULL) != SQLITE_OK)
        return Fail(error, @"Cannot validate activity boundaries");
    NSData *text = [epoch dataUsingEncoding:NSUTF8StringEncoding];
    int rc = sqlite3_bind_text(s, 1, text.bytes, (int)text.length, SQLITE_TRANSIENT) == SQLITE_OK
                 ? sqlite3_step(s)
                 : SQLITE_ERROR;
    sqlite3_finalize(s);
    return rc == SQLITE_DONE ? YES : Fail(error, @"Corrupt or unreadable activity boundaries");
}
static NSArray *Events(sqlite3 *db, NSError **error) {
    sqlite3_stmt *s = NULL;
    if (sqlite3_prepare_v2(db, "SELECT kind,epoch,t,power FROM events ORDER BY id LIMIT 200001", -1, &s,
                           NULL) != SQLITE_OK) {
        Fail(error, @"Cannot read native power stream");
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray new];
    int rc;
    while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
        if (rows.count >= 200000 || sqlite3_column_type(s, 0) != SQLITE_TEXT || !NumericColumn(s, 2)) {
            rc = SQLITE_ERROR;
            break;
        }
        NSString *kind = [[NSString alloc] initWithBytes:sqlite3_column_text(s, 0)
                                                  length:(NSUInteger)sqlite3_column_bytes(s, 0)
                                                encoding:NSUTF8StringEncoding];
        NSMutableDictionary *row =
            [@{@"kind" : kind ?: @"invalid",
               @"time" : @(sqlite3_column_double(s, 2))} mutableCopy];
        if ([kind isEqual:@"epoch"] && sqlite3_column_type(s, 1) == SQLITE_TEXT) {
            NSString *epoch = [[NSString alloc] initWithBytes:sqlite3_column_text(s, 1)
                                                       length:(NSUInteger)sqlite3_column_bytes(s, 1)
                                                     encoding:NSUTF8StringEncoding];
            row[@"epoch"] = epoch ?: @"";
        } else if ([kind isEqual:@"power"] && sqlite3_column_type(s, 3) == SQLITE_INTEGER)
            row[@"power"] = @(sqlite3_column_int(s, 3));
        [rows addObject:row];
    }
    sqlite3_finalize(s);
    if (rc != SQLITE_DONE) {
        Fail(error, @"Invalid, oversized or unreadable native power stream");
        return nil;
    }
    return rows;
}
// Fixed columns keep app identities and raw activity out of retained summaries.
static NSArray *ReadArchive(sqlite3 *db, NSError **error) {
    sqlite3_stmt *s = NULL;
    if (sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='cycle_history'", -1,
                           &s, NULL) != SQLITE_OK) {
        Fail(error, @"Cannot inspect cycle archive");
        return nil;
    }
    int rc = sqlite3_step(s);
    sqlite3_finalize(s);
    if (rc == SQLITE_DONE)
        return @[]; // Old schema-1 journals remain readable.
    if (rc != SQLITE_ROW ||
        sqlite3_prepare_v2(
            db,
            "SELECT cycle_id,start,end,duration,screen_on,screen_off,activity_pending_seconds,power_complete "
            "FROM cycle_history ORDER BY sequence DESC LIMIT 21",
            -1, &s, NULL) != SQLITE_OK) {
        Fail(error, @"Cannot read cycle archive");
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray new];
    NSMutableSet *identities = [NSMutableSet new];
    while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
        if (rows.count >= 20 || sqlite3_column_type(s, 0) != SQLITE_TEXT || sqlite3_column_bytes(s, 0) < 1 ||
            sqlite3_column_bytes(s, 0) > 1024) {
            rc = SQLITE_ERROR;
            break;
        }
        NSString *identity = [[NSString alloc] initWithBytes:sqlite3_column_text(s, 0)
                                                      length:(NSUInteger)sqlite3_column_bytes(s, 0)
                                                    encoding:NSUTF8StringEncoding];
        if (!identity || [identities containsObject:identity]) {
            rc = SQLITE_ERROR;
            break;
        }
        NSMutableDictionary *row = [@{@"id" : identity} mutableCopy];
        NSArray *keys =
            @[ @"start", @"end", @"duration", @"screen_on", @"screen_off", @"activity_pending_seconds" ];
        BOOL valid = YES;
        for (int c = 1; c <= 6; c++) {
            if ((c == 4 || c == 5) && sqlite3_column_type(s, c) == SQLITE_NULL)
                row[keys[c - 1]] = NSNull.null;
            else if (!NumericColumn(s, c) || sqlite3_column_double(s, c) < 0) {
                valid = NO;
                break;
            } else
                row[keys[c - 1]] = @(sqlite3_column_double(s, c));
        }
        double start = [row[@"start"] doubleValue], end = [row[@"end"] doubleValue],
               duration = [row[@"duration"] doubleValue];
        if (!valid || start <= 0 || end <= start || !isfinite(end - start) || duration != end - start ||
            [row[@"activity_pending_seconds"] doubleValue] > duration ||
            sqlite3_column_type(s, 7) != SQLITE_INTEGER ||
            (sqlite3_column_int64(s, 7) != 0 && sqlite3_column_int64(s, 7) != 1)) {
            rc = SQLITE_ERROR;
            break;
        }
        row[@"power_complete"] = @(sqlite3_column_int(s, 7) != 0);
        [rows addObject:row];
        [identities addObject:identity];
    }
    sqlite3_finalize(s);
    if (rc != SQLITE_DONE) {
        Fail(error, @"Invalid, oversized or unreadable cycle archive");
        return nil;
    }
    return rows;
}
static BOOL Archive(sqlite3 *db, NSDictionary *summary, NSError **error) {
    // Validate all retained records before inserting or pruning anything.
    if (!ReadArchive(db, error))
        return NO;
    if (!summary)
        return YES;
    NSMutableArray *args = [NSMutableArray new];
    for (NSString *key in @[
             @"id", @"start", @"end", @"duration", @"screen_on", @"screen_off", @"activity_pending_seconds",
             @"power_complete"
         ])
        [args addObject:summary[key]];
    return SQL(db,
               @"INSERT INTO "
               @"cycle_history(cycle_id,start,end,duration,screen_on,screen_off,activity_pending_seconds,"
               @"power_complete) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(cycle_id) DO NOTHING",
               args, error) &&
           SQL(db,
               @"DELETE FROM cycle_history WHERE sequence NOT IN (SELECT sequence FROM cycle_history ORDER "
               @"BY sequence DESC LIMIT 20)",
               @[], error);
}
// Freeze confirmed extent before a new epoch or a source gap closes the cycle.
// Closure remains incomplete; no unseen interval is stitched in.
static BOOL PreserveCheckpoint(sqlite3 *db, sqlite3_int64 *added, NSError **error) {
    if (added)
        *added = 0;
    NSArray *events = Events(db, error);
    if (!events)
        return NO;
    NSDictionary *window = IEBNativePowerWindow(events, error);
    if (!window)
        return NO;
    if (!window[@"start"] || window[@"end"])
        return YES;
    sqlite3_stmt *s = NULL;
    BOOL valid =
        sqlite3_prepare_v2(db, "SELECT epoch,checkpoint FROM meta WHERE id=1", -1, &s, NULL) == SQLITE_OK &&
        sqlite3_step(s) == SQLITE_ROW;
    NSString *epoch = valid && sqlite3_column_type(s, 0) == SQLITE_TEXT
                          ? [[NSString alloc] initWithBytes:sqlite3_column_text(s, 0)
                                                     length:(NSUInteger)sqlite3_column_bytes(s, 0)
                                                   encoding:NSUTF8StringEncoding]
                          : nil;
    double checkpoint = valid ? sqlite3_column_double(s, 1) : 0;
    valid = valid && NumericColumn(s, 1) && Date(checkpoint) && [epoch isEqual:window[@"current_epoch"]] &&
            checkpoint >= [window[@"last_native_time"] doubleValue] && [window[@"power"] isEqual:@0];
    if (s)
        sqlite3_finalize(s);
    if (!valid)
        return Fail(error, @"Cannot recover previous native checkpoint");
    if (checkpoint == [window[@"last_native_time"] doubleValue])
        return YES;
    BOOL ok = SQL(db, @"INSERT INTO events(kind,epoch,t,power) VALUES('power',?,?,0)",
                  @[ epoch, @(checkpoint) ], error);
    if (ok && added)
        *added = 1;
    return ok;
}
@interface IEBNativeJournal () {
    sqlite3 *_db;
    int _lockFD;
    sqlite3_int64 _activityRows, _eventRows;
    double _deadline, _started, _lastPowerTime, _windowStart;
    NSInteger _power;
    sqlite3_int64 _attachedID;
}
@property(nonatomic, copy) NSString *epoch;
@property(nonatomic, copy) NSString *directory;
@end
@implementation IEBNativeJournal
- (instancetype)initWithDirectory:(NSString *)directory
                            epoch:(NSString *)epoch
                       nativeTime:(double)time
                            error:(NSError **)error {
    self = [super init];
    if (!self)
        return nil;
    _lockFD = -1;
    if (error)
        *error = nil;
    if (!Date(time) || ![epoch isKindOfClass:NSString.class] || !epoch.length || epoch.length > 128) {
        Fail(error, @"Invalid journal epoch");
        return nil;
    }
    _lockFD = Lock(directory, error);
    if (_lockFD < 0)
        return nil;
    _db = Open(directory, YES, error);
    if (!_db)
        return nil;
    _deadline = Now() + 5;
    if (!isfinite(_deadline)) {
        Fail(error, @"Journal deadline unavailable");
        return nil;
    }
    sqlite3_progress_handler(_db, 1000, Expired, &_deadline);
    sqlite3_stmt *version = NULL;
    int userVersion = -1;
    if (sqlite3_prepare_v2(_db, "PRAGMA user_version", -1, &version, NULL) == SQLITE_OK &&
        sqlite3_step(version) == SQLITE_ROW)
        userVersion = sqlite3_column_int(version, 0);
    if (version)
        sqlite3_finalize(version);
    if (userVersion != 0 && userVersion != 1) {
        Fail(error, @"Unsupported native journal schema");
        return nil;
    }
    // WAL reader snapshots stay consistent with the writer; FULL commits retain accepted records.
    if (sqlite3_exec(_db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA max_page_count=16384;",
                     NULL, NULL, NULL) != SQLITE_OK) {
        Fail(error, @"Cannot configure native journal durability");
        return nil;
    }
    if (!SQL(_db, @"BEGIN IMMEDIATE", @[], error))
        return nil;
    NSArray *schema = @[
        @"CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY,kind TEXT NOT NULL,epoch TEXT NOT NULL,t REAL NOT NULL,power INTEGER)",
        @"CREATE UNIQUE INDEX IF NOT EXISTS epoch_once ON events(epoch) WHERE kind='epoch'",
        @"CREATE TABLE IF NOT EXISTS activities(id INTEGER PRIMARY KEY,epoch TEXT NOT NULL,a REAL NOT NULL,b REAL NOT NULL,app TEXT,metrics BLOB NOT NULL)",
        @"CREATE INDEX IF NOT EXISTS activities_scope ON activities(epoch,b)",
        @"CREATE TABLE IF NOT EXISTS cycle_history(sequence INTEGER PRIMARY KEY AUTOINCREMENT,cycle_id TEXT NOT NULL UNIQUE,start REAL NOT NULL,end REAL NOT NULL,duration REAL NOT NULL,screen_on REAL,screen_off REAL,activity_pending_seconds REAL NOT NULL,power_complete INTEGER NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS meta(id INTEGER PRIMARY KEY CHECK(id=1),epoch TEXT NOT NULL,checkpoint REAL NOT NULL,wall REAL NOT NULL,writer INTEGER NOT NULL,source_failed INTEGER NOT NULL)"
    ];
    BOOL ok = YES;
    for (NSString *s in schema)
        if (!SQL(_db, s, @[], error)) {
            ok = NO;
            break;
        }
    if (ok)
        ok = PreserveCheckpoint(_db, NULL, error);
    if (ok)
        ok = SQL(_db, @"INSERT INTO events(kind,epoch,t) VALUES('epoch',?,?)", @[ epoch, @(time) ], error) &&
             SQL(_db, @"INSERT OR REPLACE INTO meta VALUES(1,?,?,?,?,0)",
                 @[ epoch, @(time), @(NSDate.date.timeIntervalSince1970), @(getpid()) ], error) &&
             SQL(_db, @"PRAGMA user_version=1", @[], error);
    if (ok)
        ok = SQL(_db, @"COMMIT", @[], error);
    if (!ok) {
        if (!SQL(_db, @"ROLLBACK", @[], NULL))
            Fail(error, @"Journal initialization rollback failed");
        return nil;
    }
    sqlite3_stmt *count = NULL;
    BOOL counted =
        sqlite3_prepare_v2(_db, "SELECT (SELECT count(*) FROM activities),(SELECT count(*) FROM events)", -1,
                           &count, NULL) == SQLITE_OK &&
        sqlite3_step(count) == SQLITE_ROW;
    if (counted) {
        _activityRows = sqlite3_column_int64(count, 0);
        _eventRows = sqlite3_column_int64(count, 1);
    }
    if (count)
        sqlite3_finalize(count);
    if (!counted || _activityRows > 200000 || _eventRows >= 200000) {
        Fail(error, @"Cannot count journal records or journal limit reached");
        return nil;
    }
    _epoch = [epoch copy];
    _directory = [directory copy];
    _started = time;
    _lastPowerTime = time;
    _power = -1;
    return self;
}
- (BOOL)begin:(NSError **)error {
    if (error)
        *error = nil;
    _deadline = Now() + 5;
    return isfinite(_deadline) ? SQL(_db, @"BEGIN IMMEDIATE", @[], error)
                               : Fail(error, @"Journal deadline unavailable");
}
- (BOOL)finish:(BOOL)ok error:(NSError **)error {
    if (ok)
        ok = SQL(_db, @"COMMIT", @[], error);
    if (!ok && !SQL(_db, @"ROLLBACK", @[], NULL))
        Fail(error, @"Journal rollback failed");
    return ok;
}
- (BOOL)touch:(double)t error:(NSError **)error {
    return SQL(_db, @"UPDATE meta SET checkpoint=MAX(checkpoint,?),wall=? WHERE id=1",
               @[ @(t), @(NSDate.date.timeIntervalSince1970) ], error);
}
- (BOOL)markSourceFailed:(NSError **)error {
    return [self begin:error] &&
           [self finish:SQL(_db, @"UPDATE meta SET source_failed=1 WHERE id=1", @[], error) error:error];
}
- (BOOL)recordPower:(NSInteger)power nativeTime:(double)time error:(NSError **)error {
    if (error)
        *error = nil;
    if ((power != 0 && power != 1) || !Date(time))
        return Fail(error, @"Invalid native external power observation");
    // Native registration can deliver a cached record preceding this capture epoch.
    if (time < _started)
        return YES;
    if (time < _lastPowerTime || (time == _lastPowerTime && _power != -1 && power != _power))
        return Fail(error, @"Out-of-order native power observation");
    if (![self begin:error])
        return NO;
    BOOL detach = _power == 1 && power == 0;
    BOOL ok = YES;
    sqlite3_int64 removed = 0, removedEvents = 0;
    if (detach) {
        // This independent WAL reader sees the committed old cycle while our writer
        // transaction protects archive+pruning as one durable operation.
        NSError *archiveError = nil;
        NSDictionary *capture = IEBReadNativeJournal(self.directory, &archiveError);
        NSDictionary *summary = capture ? IEBSummarizeClosedCycle(capture, &archiveError) : nil;
        ok = capture && !archiveError && Archive(_db, summary, &archiveError);
        if (!ok && error)
            *error = archiveError;
        if (ok)
            ok = SQL(_db, @"DELETE FROM activities WHERE epoch<>? OR b<=?", @[ self.epoch, @(time) ], error);
        if (ok)
            removed = sqlite3_changes(_db);
        if (ok) {
            ok = SQL(_db, @"DELETE FROM events WHERE epoch<>? OR (kind<>'epoch' AND id<?)",
                     @[ self.epoch, @(_attachedID) ], error);
            if (ok)
                removedEvents = sqlite3_changes(_db);
        }
        if (ok)
            ok = SQL(_db, @"UPDATE meta SET source_failed=0 WHERE id=1", @[], error);
    }
    if (ok && _eventRows - removedEvents >= 199999) {
        [self finish:NO error:NULL];
        if ([self begin:error])
            [self finish:SQL(_db, @"UPDATE meta SET source_failed=1 WHERE id=1", @[], error) error:error];
        return Fail(error, @"Native power journal row limit reached");
    }
    if (ok)
        ok = SQL(_db, @"INSERT INTO events(kind,epoch,t,power) VALUES('power',?,?,?)",
                 @[ self.epoch, @(time), @(power) ], error) &&
             [self touch:time error:error];
    sqlite3_int64 row = sqlite3_last_insert_rowid(_db);
    ok = [self finish:ok error:error];
    if (ok) {
        _activityRows -= removed;
        _eventRows += 1 - removedEvents;
        _power = power;
        _lastPowerTime = time;
        if (power == 1)
            _attachedID = row;
        if (detach)
            _windowStart = time;
    }
    return ok;
}
- (BOOL)recordGapAtNativeTime:(double)time error:(NSError **)error {
    if (!Date(time) || time < _lastPowerTime || _eventRows >= 200000)
        return Fail(error, @"Invalid native source gap or journal limit reached");
    if (![self begin:error])
        return NO;
    // Freeze only the extent confirmed before this gap, just as on restart.
    // Reading the old checkpoint first also rejects late gaps that would put
    // the synthetic power observation after the gap in source order.
    sqlite3_stmt *checkpoint = NULL;
    BOOL ok = sqlite3_prepare_v2(_db, "SELECT checkpoint FROM meta WHERE id=1", -1, &checkpoint, NULL) ==
                  SQLITE_OK &&
              sqlite3_step(checkpoint) == SQLITE_ROW && NumericColumn(checkpoint, 0) &&
              Date(sqlite3_column_double(checkpoint, 0)) && sqlite3_column_double(checkpoint, 0) <= time;
    if (checkpoint)
        sqlite3_finalize(checkpoint);
    if (!ok)
        Fail(error, @"Native source gap precedes or cannot read confirmed checkpoint");
    sqlite3_int64 added = 0;
    if (ok)
        ok = PreserveCheckpoint(_db, &added, error);
    if (ok && _eventRows + added + 1 > 200000)
        ok = Fail(error, @"Native power journal row limit reached");
    if (ok)
        ok = SQL(_db, @"INSERT INTO events(kind,epoch,t) VALUES('gap',?,?)", @[ self.epoch, @(time) ],
                 error) &&
             [self touch:time error:error];
    ok = [self finish:ok error:error];
    if (ok) {
        _power = -1;
        _lastPowerTime = time;
        _eventRows += added + 1;
        _windowStart = 0;
    }
    return ok;
}
- (BOOL)recordActivity:(NSDictionary *)entry start:(NSDate *)start end:(NSDate *)end error:(NSError **)error {
    if (error)
        *error = nil;
    NSError *validation = nil;
    NSDictionary *record = IEBActivityEvidence(entry, start, end, &validation);
    if (!record) {
        if (error)
            *error = validation;
        return validation == nil;
    }
    if (!_windowStart || end.timeIntervalSince1970 <= _windowStart)
        return YES;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record[@"metrics"]
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data || data.length > 8192)
        return data ? Fail(error, @"Oversized native activity record") : NO;
    if (![self begin:error])
        return NO;
    if (_activityRows >= 200000) {
        BOOL marked = SQL(_db, @"UPDATE meta SET source_failed=1 WHERE id=1", @[], error);
        [self finish:marked error:error];
        return Fail(error, @"Native activity journal row limit reached");
    }
    BOOL ok = SQL(_db, @"INSERT INTO activities(epoch,a,b,app,metrics) VALUES(?,?,?,?,?)",
                  @[ self.epoch, record[@"start"], record[@"end"], entry[@"BundleID"] ?: NSNull.null, data ],
                  error) &&
              [self touch:end.timeIntervalSince1970 error:error];
    ok = [self finish:ok error:error];
    if (ok)
        _activityRows++;
    return ok;
}
- (BOOL)checkpointAtNativeTime:(double)time error:(NSError **)error {
    if (!Date(time) || time < _lastPowerTime)
        return Fail(error, @"Invalid native checkpoint");
    return [self begin:error] && [self finish:[self touch:time error:error] error:error];
}
- (void)dealloc {
    if (_db)
        sqlite3_close(_db);
    if (_lockFD >= 0) {
        flock(_lockFD, LOCK_UN);
        close(_lockFD);
    }
}
@end

static NSDictionary *ReadJournal(NSString *directory, double selectedStart, double selectedEnd,
                                 NSError **error, sqlite3 *snapshot) {
    if (error)
        *error = nil;
    BOOL selected = selectedStart != 0 || selectedEnd != 0;
    if (selected && (!Date(selectedStart) || !Date(selectedEnd) || selectedEnd <= selectedStart)) {
        Fail(error, @"Invalid selected activity range");
        return nil;
    }
    sqlite3 *db = snapshot ?: Open(directory, NO, error);
    if (!db)
        return nil;
    double deadline = Now() + 5;
    sqlite3_progress_handler(db, 1000, Expired, &deadline);
    NSMutableDictionary *result = nil;
    sqlite3_stmt *s = NULL;
    NSArray *events = nil;
    NSDictionary *window = nil;
    NSMutableDictionary *w = nil, *apps = nil, *global = nil;
    NSMutableArray *buckets = nil;
    NSString *epoch = nil, *writerEpoch = nil;
    NSData *epochData = nil;
    if (!isfinite(deadline) || (!snapshot && !SQL(db, @"BEGIN", @[], error)))
        goto done;
    if (sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &s, NULL) != SQLITE_OK ||
        sqlite3_step(s) != SQLITE_ROW || sqlite3_column_int(s, 0) != 1) {
        Fail(error, @"Unsupported native journal schema");
        goto done;
    }
    sqlite3_finalize(s);
    s = NULL;
    if (sqlite3_prepare_v2(db, "SELECT checkpoint,wall,writer,source_failed,epoch FROM meta WHERE id=1", -1,
                           &s, NULL) != SQLITE_OK ||
        sqlite3_step(s) != SQLITE_ROW) {
        Fail(error, @"Missing native journal metadata");
        goto done;
    }
    if (!NumericColumn(s, 0) || !NumericColumn(s, 1) || sqlite3_column_type(s, 2) != SQLITE_INTEGER ||
        sqlite3_column_type(s, 3) != SQLITE_INTEGER || sqlite3_column_int64(s, 2) < 1 ||
        sqlite3_column_int64(s, 2) > INT_MAX ||
        (sqlite3_column_int64(s, 3) != 0 && sqlite3_column_int64(s, 3) != 1)) {
        Fail(error, @"Invalid journal metadata types");
        goto done;
    }
    if (sqlite3_column_type(s, 4) != SQLITE_TEXT || sqlite3_column_bytes(s, 4) < 1 ||
        sqlite3_column_bytes(s, 4) > 512) {
        Fail(error, @"Invalid native writer epoch");
        goto done;
    }
    writerEpoch = [[NSString alloc] initWithBytes:sqlite3_column_text(s, 4)
                                           length:(NSUInteger)sqlite3_column_bytes(s, 4)
                                         encoding:NSUTF8StringEncoding];
    if (!writerEpoch) {
        Fail(error, @"Invalid native writer epoch encoding");
        goto done;
    }
    double checkpoint = sqlite3_column_double(s, 0), wall = sqlite3_column_double(s, 1);
    int writer = sqlite3_column_int(s, 2), failed = sqlite3_column_int(s, 3);
    sqlite3_finalize(s);
    s = NULL;
    if (!Date(checkpoint) || !Date(wall) || writer <= 0 || (failed != 0 && failed != 1)) {
        Fail(error, @"Invalid native journal metadata");
        goto done;
    }
    events = Events(db, error);
    if (!events)
        goto done;
    window = IEBNativePowerWindow(events, error);
    if (!window)
        goto done;
    w = [window mutableCopy];
    if (failed && !window[@"end"])
        w[@"power_complete"] = @NO;
    result = [@{
        @"window" : w,
        @"available" : @NO,
        @"source_coverage_verified" : @NO,
        @"source_failed" : @(failed != 0),
        @"observed_wall_time" : @(wall),
        @"checkpoint_native_time" : @(checkpoint),
        @"writer_pid" : @(writer),
        @"writer_epoch" : writerEpoch
    } mutableCopy];
    if (!window[@"start"]) {
        if (selected) {
            result = nil;
            Fail(error, @"No unplug cycle for selection");
            goto done;
        }
        goto commit;
    }
    double a = [window[@"start"] doubleValue], b = window[@"end"] ? [window[@"end"] doubleValue] : checkpoint;
    if (!ValidBounds(db, window[@"epoch"], error)) {
        result = nil;
        goto done;
    }
    w[@"effective_end"] = @(b);
    if (selected) {
        if (selectedStart < a || selectedEnd > b) {
            result = nil;
            Fail(error, @"Selection is outside the saved cycle");
            goto done;
        }
        a = selectedStart;
        b = selectedEnd;
    }
    result[@"range"] = @{@"start" : @(a), @"end" : @(b)};
    if (b <= a)
        goto commit;
    double span = b - a;
    // Nice time intervals with enough bars on both sides of the one-hour boundary.
    double width = 60;
    const double steps[] = {60, 300, 900, 1800, 3600, 10800, 21600};
    for (NSUInteger i = 0; i < sizeof(steps) / sizeof(steps[0]); i++) {
        width = steps[i];
        if (ceil(span / width) <= 48)
            break;
    }
    width = MAX(width, ceil(span / 96));
    if (!isfinite(span) || !isfinite(width) || width <= 0) {
        result = nil;
        Fail(error, @"Invalid activity bucket range");
        goto done;
    }
    buckets = [NSMutableArray new];
    NSUInteger bucketCount = (NSUInteger)ceil(span / width);
    for (NSUInteger i = 0; i < bucketCount; i++)
        [buckets addObject:[@{
                     @"start" : @(a + i * width),
                     @"end" : @(MIN(b, a + (i + 1) * width)),
                     @"ScreenOn" : NSNull.null,
                     @"ScreenOff" : NSNull.null
                 } mutableCopy]];
    result[@"activity_buckets"] = buckets;
    apps = [NSMutableDictionary new];
    global = [NSMutableDictionary new];
    NSUInteger count = 0, boundaries = 0;
    double latestGlobalEnd = 0;
    if (sqlite3_prepare_v2(
            db,
            "SELECT a,b,app,metrics FROM activities WHERE epoch=? AND b>? AND a<? ORDER BY id LIMIT 200001",
            -1, &s, NULL) != SQLITE_OK) {
        result = nil;
        Fail(error, @"Cannot query native activity intervals");
        goto done;
    }
    epoch = window[@"epoch"];
    epochData = [epoch dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_text(s, 1, epochData.bytes, (int)epochData.length, SQLITE_TRANSIENT);
    sqlite3_bind_double(s, 2, a);
    sqlite3_bind_double(s, 3, b);
    int rc;
    while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
        if (Now() > deadline) {
            rc = SQLITE_INTERRUPT;
            break;
        }
        double start = sqlite3_column_double(s, 0), end = sqlite3_column_double(s, 1);
        int bytes = sqlite3_column_bytes(s, 3);
        if (count >= 200000 || !NumericColumn(s, 0) || !NumericColumn(s, 1) || !Date(start) || !Date(end) ||
            end <= start || bytes <= 0 || bytes > 8192 || sqlite3_column_type(s, 3) != SQLITE_BLOB) {
            rc = SQLITE_ERROR;
            break;
        }
        NSString *app = nil;
        if (sqlite3_column_type(s, 2) != SQLITE_NULL) {
            if (sqlite3_column_type(s, 2) != SQLITE_TEXT || sqlite3_column_bytes(s, 2) > 4096) {
                rc = SQLITE_ERROR;
                break;
            }
            app = [[NSString alloc] initWithBytes:sqlite3_column_text(s, 2)
                                           length:(NSUInteger)sqlite3_column_bytes(s, 2)
                                         encoding:NSUTF8StringEncoding];
            if (!app) {
                rc = SQLITE_ERROR;
                break;
            }
        }
        NSData *data = [NSData dataWithBytes:sqlite3_column_blob(s, 3) length:(NSUInteger)bytes];
        id raw = [NSPropertyListSerialization propertyListWithData:data
                                                           options:NSPropertyListImmutable
                                                            format:NULL
                                                             error:error];
        if (![raw isKindOfClass:NSDictionary.class]) {
            rc = SQLITE_ERROR;
            break;
        }
        NSMutableDictionary *entry = [raw mutableCopy];
        if (app)
            entry[@"BundleID"] = app;
        NSDictionary *validated = IEBActivityEvidence(entry, [NSDate dateWithTimeIntervalSince1970:start],
                                                      [NSDate dateWithTimeIntervalSince1970:end], error);
        if (!validated || [validated[@"metrics"] count] != [raw count]) {
            rc = SQLITE_ERROR;
            break;
        }
        if (!app)
            latestGlobalEnd = MAX(latestGlobalEnd, MIN(b, end));
        double weight = (MIN(b, end) - MAX(a, start)) / (end - start);
        NSMutableDictionary *totals = global;
        if (app) {
            if (!apps[app])
                apps[app] = [NSMutableDictionary new];
            totals = apps[app];
        }
        BOOL finite = YES;
        for (NSString *key in validated[@"metrics"]) {
            double sum = [totals[key] doubleValue] + [validated[@"metrics"][key] doubleValue] * weight;
            if (!isfinite(sum)) {
                finite = NO;
                break;
            }
            totals[key] = @(sum);
        }
        if (!finite) {
            rc = SQLITE_ERROR;
            break;
        }
        if (!app)
            for (NSMutableDictionary *bucket in buckets) {
                double overlap =
                    MIN([bucket[@"end"] doubleValue], end) - MAX([bucket[@"start"] doubleValue], start);
                if (overlap <= 0)
                    continue;
                for (NSString *key in @[ @"ScreenOn", @"ScreenOff" ]) {
                    if (!validated[@"metrics"][key])
                        continue;
                    double value = (bucket[key] == NSNull.null ? 0 : [bucket[key] doubleValue]) +
                                   [validated[@"metrics"][key] doubleValue] * overlap / (end - start);
                    if (!isfinite(value)) {
                        rc = SQLITE_ERROR;
                        finite = NO;
                        break;
                    }
                    bucket[key] = @(value);
                }
                if (!finite)
                    break;
            }
        if (!finite)
            break;
        count++;
        if (start < a || end > b)
            boundaries++;
    }
    sqlite3_finalize(s);
    s = NULL;
    if (rc != SQLITE_DONE) {
        result = nil;
        Fail(error, @"Invalid, oversized or unreadable native activity snapshot");
        goto done;
    }
    result[@"available"] = @YES;
    result[@"apps"] = apps;
    result[@"app_count"] = @(apps.count);
    result[@"global_metrics"] = global;
    result[@"activity_latest_end"] = latestGlobalEnd > 0 ? @(latestGlobalEnd) : NSNull.null;
    result[@"overlapping_interval_count"] = @(count);
    result[@"boundary_interval_count"] = @(boundaries);
commit:
    if (!snapshot && !SQL(db, @"COMMIT", @[], error))
        result = nil;
done:
    if (s)
        sqlite3_finalize(s);
    if (!snapshot && !sqlite3_get_autocommit(db)) {
        if (!SQL(db, @"ROLLBACK", @[], NULL)) {
            Fail(error, @"Native journal read rollback failed");
            result = nil;
        }
    }
    // The progress callback points at this stack frame; the owner installs its
    // own deadline again before continuing a shared read transaction.
    sqlite3_progress_handler(db, 0, NULL, NULL);
    if (!snapshot)
        sqlite3_close(db);
    return result;
}

NSDictionary *IEBReadNativeJournal(NSString *directory, NSError **error) {
    return ReadJournal(directory, 0, 0, error, NULL);
}
NSDictionary *IEBReadNativeJournalSelection(NSString *directory, double start, double end, NSError **error) {
    if (start == 0 && end == 0) {
        Fail(error, @"Invalid empty selection");
        return nil;
    }
    return ReadJournal(directory, start, end, error, NULL);
}

NSArray<NSDictionary *> *IEBReadNativeCycleHistory(NSString *directory, NSError **error) {
    if (error)
        *error = nil;
    sqlite3 *db = Open(directory, NO, error);
    if (!db)
        return nil;
    double deadline = Now() + 5;
    NSError *readError = nil;
    NSDictionary *current = nil;
    NSArray *saved = nil;
    // Current closure and archived summaries must come from the same WAL snapshot.
    if (isfinite(deadline) && SQL(db, @"BEGIN", @[], &readError)) {
        NSDictionary *capture = ReadJournal(directory, 0, 0, &readError, db);
        current = capture ? IEBSummarizeClosedCycle(capture, &readError) : nil;
        sqlite3_progress_handler(db, 1000, Expired, &deadline);
        if (capture && !readError)
            saved = ReadArchive(db, &readError);
        if (saved && !SQL(db, @"COMMIT", @[], &readError))
            saved = nil;
    } else if (!readError)
        Fail(&readError, @"Cycle archive deadline unavailable");
    if (!sqlite3_get_autocommit(db) && !SQL(db, @"ROLLBACK", @[], NULL)) {
        saved = nil;
        Fail(&readError, @"Cycle archive rollback failed");
    }
    sqlite3_close(db);
    if (!saved) {
        if (error)
            *error = readError;
        return nil;
    }
    NSMutableArray *result = [saved mutableCopy];
    BOOL found = NO;
    for (NSDictionary *row in saved)
        if ([row[@"id"] isEqual:current[@"id"]]) {
            found = YES;
            break;
        }
    if (current && !found)
        [result insertObject:current atIndex:0];
    if (result.count > 20)
        [result removeLastObject];
    return [result copy];
}
