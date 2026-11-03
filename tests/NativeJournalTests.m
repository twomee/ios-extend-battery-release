#import "../Sources/Statistics/IEBCycleHistory.h"
#import "../Sources/Statistics/IEBNativeJournal.h"
#import <sqlite3.h>
#import <sys/stat.h>
#import <unistd.h>
#define REQUIRE(...)                                                                                         \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "Journal FAIL %d: %s\n", __LINE__, #__VA_ARGS__);                                \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDate *D(double x) { return [NSDate dateWithTimeIntervalSince1970:x]; }
int main(void) {
    @autoreleasepool {
        // Crossing an hour must retain meaningful, independently tappable buckets.
        for (NSNumber *span in @[ @3540, @3600, @3685, @7200, @86400, @864000 ]) {
            NSString *bucketDir =
                [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            REQUIRE([NSFileManager.defaultManager createDirectoryAtPath:bucketDir
                                            withIntermediateDirectories:NO
                                                             attributes:@{
                                                                 NSFilePosixPermissions : @0700
                                                             }
                                                                  error:NULL]);
            NSError *bucketError = nil;
            IEBNativeJournal *fixture = [[IEBNativeJournal alloc] initWithDirectory:bucketDir
                                                                              epoch:@"bucket"
                                                                         nativeTime:100
                                                                              error:&bucketError];
            REQUIRE(fixture && [fixture recordPower:1 nativeTime:100 error:&bucketError]);
            REQUIRE([fixture recordPower:0 nativeTime:110 error:&bucketError]);
            REQUIRE([fixture checkpointAtNativeTime:110 + span.doubleValue error:&bucketError]);
            NSDictionary *graph = IEBReadNativeJournal(bucketDir, &bucketError);
            NSArray *parts = graph[@"activity_buckets"];
            REQUIRE(graph && !bucketError && parts.count >= 12 && parts.count <= 96);
            double previous = 110;
            for (NSDictionary *part in parts) {
                REQUIRE([part[@"start"] doubleValue] == previous);
                REQUIRE([part[@"end"] doubleValue] > previous);
                previous = [part[@"end"] doubleValue];
            }
            REQUIRE(previous == 110 + span.doubleValue);
            fixture = nil;
            REQUIRE([NSFileManager.defaultManager removeItemAtPath:bucketDir error:NULL]);
        }
        // A gap must retain the already confirmed extent, and fail atomically.
        NSString *gapDir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        REQUIRE([NSFileManager.defaultManager createDirectoryAtPath:gapDir
                                        withIntermediateDirectories:NO
                                                         attributes:@{
                                                             NSFilePosixPermissions : @0700
                                                         }
                                                              error:NULL]);
        NSError *gapError = nil;
        IEBNativeJournal *gapJournal = [[IEBNativeJournal alloc] initWithDirectory:gapDir
                                                                             epoch:@"gap"
                                                                        nativeTime:100
                                                                             error:&gapError];
        REQUIRE(gapJournal && [gapJournal recordPower:1 nativeTime:100 error:&gapError]);
        REQUIRE([gapJournal recordPower:0 nativeTime:110 error:&gapError]);
        REQUIRE([gapJournal recordActivity:@{@"ScreenOn" : @80} start:D(110) end:D(190) error:&gapError]);
        REQUIRE([gapJournal checkpointAtNativeTime:200 error:&gapError]);
        // A late gap cannot precede a checkpoint already used by readers.
        REQUIRE(![gapJournal recordGapAtNativeTime:199 error:&gapError] && gapError);
        sqlite3 *gapDB = NULL;
        REQUIRE(sqlite3_open([[gapDir stringByAppendingPathComponent:@"native-journal.sqlite"]
                                 fileSystemRepresentation],
                             &gapDB) == SQLITE_OK);
        REQUIRE(sqlite3_exec(gapDB,
                             "CREATE TRIGGER reject_gap BEFORE INSERT ON events WHEN NEW.kind='gap' "
                             "BEGIN SELECT RAISE(ABORT,'fixture gap storage failure'); END",
                             NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(![gapJournal recordGapAtNativeTime:210 error:&gapError] && gapError);
        NSDictionary *beforeGap = IEBReadNativeJournal(gapDir, &gapError);
        REQUIRE(beforeGap && !gapError && !beforeGap[@"window"][@"end"] &&
                [beforeGap[@"window"][@"power_complete"] boolValue] &&
                [beforeGap[@"window"][@"effective_end"] isEqual:@200]);
        sqlite3_stmt *gapCount = NULL;
        REQUIRE(sqlite3_prepare_v2(gapDB, "SELECT count(*) FROM events", -1, &gapCount, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_step(gapCount) == SQLITE_ROW && sqlite3_column_int(gapCount, 0) == 3);
        REQUIRE(sqlite3_finalize(gapCount) == SQLITE_OK);
        REQUIRE(sqlite3_exec(gapDB, "DROP TRIGGER reject_gap", NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(gapDB) == SQLITE_OK);
        REQUIRE([gapJournal recordGapAtNativeTime:210 error:&gapError]);
        NSDictionary *gapCapture = IEBReadNativeJournal(gapDir, &gapError);
        REQUIRE(gapCapture && !gapError && [gapCapture[@"available"] boolValue]);
        REQUIRE([gapCapture[@"window"][@"end"] isEqual:@200] &&
                ![gapCapture[@"window"][@"power_complete"] boolValue]);
        REQUIRE([gapCapture[@"global_metrics"][@"ScreenOn"] isEqual:@80]);
        NSDictionary *gapSummary = IEBSummarizeClosedCycle(gapCapture, &gapError);
        REQUIRE([gapSummary[@"duration"] isEqual:@90] && [gapSummary[@"screen_on"] isEqual:@80]);
        REQUIRE([IEBReadNativeCycleHistory(gapDir, &gapError)[0] isEqual:gapSummary]);
        REQUIRE(sqlite3_open([[gapDir stringByAppendingPathComponent:@"native-journal.sqlite"]
                                 fileSystemRepresentation],
                             &gapDB) == SQLITE_OK);
        REQUIRE(sqlite3_prepare_v2(gapDB, "SELECT count(*) FROM events", -1, &gapCount, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_step(gapCount) == SQLITE_ROW && sqlite3_column_int(gapCount, 0) == 5);
        REQUIRE(sqlite3_finalize(gapCount) == SQLITE_OK);
        REQUIRE(sqlite3_close(gapDB) == SQLITE_OK);
        // Once closed, another gap cannot extend or duplicate the preserved cycle.
        REQUIRE([gapJournal recordGapAtNativeTime:211 error:&gapError]);
        REQUIRE([IEBReadNativeCycleHistory(gapDir, &gapError)[0] isEqual:gapSummary]);
        gapJournal = nil;
        // At the cap, an already closed cycle needs only the gap row. The next
        // gap must fail without allowing the internal count to exceed storage.
        REQUIRE(sqlite3_open([[gapDir stringByAppendingPathComponent:@"native-journal.sqlite"]
                                 fileSystemRepresentation],
                             &gapDB) == SQLITE_OK);
        REQUIRE(sqlite3_exec(gapDB,
                             "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<199992) "
                             "INSERT INTO events(kind,epoch,t) SELECT 'gap','gap',211 FROM n",
                             NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(gapDB) == SQLITE_OK);
        gapJournal = [[IEBNativeJournal alloc] initWithDirectory:gapDir
                                                           epoch:@"limit"
                                                      nativeTime:220
                                                           error:&gapError];
        REQUIRE(gapJournal && !gapError);
        REQUIRE([gapJournal recordGapAtNativeTime:230 error:&gapError]);
        REQUIRE(![gapJournal recordGapAtNativeTime:231 error:&gapError] && gapError);
        REQUIRE(sqlite3_open([[gapDir stringByAppendingPathComponent:@"native-journal.sqlite"]
                                 fileSystemRepresentation],
                             &gapDB) == SQLITE_OK);
        REQUIRE(sqlite3_prepare_v2(gapDB, "SELECT count(*) FROM events", -1, &gapCount, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_step(gapCount) == SQLITE_ROW && sqlite3_column_int(gapCount, 0) == 200000);
        REQUIRE(sqlite3_finalize(gapCount) == SQLITE_OK);
        REQUIRE(sqlite3_close(gapDB) == SQLITE_OK);
        gapJournal = nil;
        REQUIRE([NSFileManager.defaultManager removeItemAtPath:gapDir error:NULL]);
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSFileManager *fm = NSFileManager.defaultManager;
        REQUIRE([fm createDirectoryAtPath:dir
              withIntermediateDirectories:NO
                               attributes:@{
                                   NSFilePosixPermissions : @0700
                               }
                                    error:NULL]);
        NSError *error = nil;
        mode_t previousMask = umask(0777);
        IEBNativeJournal *j = [[IEBNativeJournal alloc] initWithDirectory:dir
                                                                    epoch:@"first"
                                                               nativeTime:100
                                                                    error:&error];
        umask(previousMask);
        if (!j || error)
            fprintf(stderr, "Init error: %s\n", error.description.UTF8String);
        REQUIRE(j && !error);
        IEBNativeJournal *competing = [[IEBNativeJournal alloc] initWithDirectory:dir
                                                                            epoch:@"competing"
                                                                       nativeTime:101
                                                                            error:&error];
        REQUIRE(!competing && error);
        REQUIRE([j recordPower:1 nativeTime:100 error:&error]);
        REQUIRE([j recordPower:0 nativeTime:110 error:&error]);
        REQUIRE([j checkpointAtNativeTime:120 error:&error]);
        NSDictionary *empty = IEBReadNativeJournal(dir, &error);
        REQUIRE(empty[@"activity_latest_end"] == NSNull.null);
        REQUIRE(empty[@"activity_buckets"][0][@"ScreenOn"] == NSNull.null &&
                empty[@"activity_buckets"][0][@"ScreenOff"] == NSNull.null);
        REQUIRE([j recordActivity:@{
            @"BundleID" : @"app.test",
            @"ScreenOnTime" : @20
        }
                            start:D(105)
                              end:D(125)
                            error:&error]);
        REQUIRE([j recordActivity:@{@"ScreenOn" : @10} start:D(115) end:D(125) error:&error]);
        NSDictionary *onlyOn = IEBReadNativeJournal(dir, &error);
        REQUIRE(onlyOn[@"activity_buckets"][0][@"ScreenOff"] == NSNull.null);
        REQUIRE([j recordActivity:@{@"ScreenOff" : @0} start:D(115) end:D(125) error:&error]);
        REQUIRE([IEBReadNativeJournal(dir, &error)[@"activity_buckets"][0][@"ScreenOff"] isEqual:@0]);
        REQUIRE([j checkpointAtNativeTime:130 error:&error]);
        NSDictionary *r = IEBReadNativeJournal(dir, &error);
        REQUIRE(r && !error && [r[@"window"][@"start"] doubleValue] == 110 &&
                [r[@"window"][@"effective_end"] doubleValue] == 130);
        REQUIRE([r[@"activity_latest_end"] doubleValue] == 125);
        REQUIRE([r[@"app_count"] integerValue] == 1 &&
                [r[@"apps"][@"app.test"][@"ScreenOnTime"] doubleValue] == 15);
        REQUIRE([r[@"global_metrics"][@"ScreenOn"] doubleValue] == 10 &&
                [r[@"boundary_interval_count"] integerValue] == 1);
        REQUIRE(![r[@"source_coverage_verified"] boolValue]);
        NSDictionary *selected = IEBReadNativeJournalSelection(dir, 115, 120, &error);
        REQUIRE(selected && !error && [selected[@"apps"][@"app.test"][@"ScreenOnTime"] doubleValue] == 5);
        REQUIRE([selected[@"activity_buckets"] count] == 1 &&
                [selected[@"activity_buckets"][0][@"ScreenOn"] doubleValue] == 5);
        REQUIRE(!IEBReadNativeJournalSelection(dir, 109, 120, &error) && error);
        REQUIRE(!IEBReadNativeJournalSelection(dir, 120, 115, &error) && error);
        sqlite3 *edit = NULL;
        NSString *dbPath = [dir stringByAppendingPathComponent:@"native-journal.sqlite"];
        REQUIRE(sqlite3_open(dbPath.fileSystemRepresentation, &edit) == SQLITE_OK);
        REQUIRE(sqlite3_exec(edit, "UPDATE activities SET a='corrupt',b=0 WHERE id=1", NULL, NULL, NULL) ==
                SQLITE_OK);
        REQUIRE(!IEBReadNativeJournal(dir, &error) && error);
        REQUIRE(sqlite3_exec(edit, "UPDATE activities SET a=105,b=125 WHERE id=1", NULL, NULL, NULL) ==
                SQLITE_OK);
        REQUIRE(sqlite3_exec(edit, "PRAGMA user_version=2", NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(!IEBReadNativeJournal(dir, &error) && error);
        REQUIRE(sqlite3_exec(edit, "PRAGMA user_version=1", NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(edit) == SQLITE_OK);
        REQUIRE([j recordPower:1 nativeTime:140 error:&error]);
        REQUIRE([j recordPower:1 nativeTime:160 error:&error]);
        r = IEBReadNativeJournal(dir, &error);
        REQUIRE([r[@"window"][@"end"] doubleValue] == 140 && [r[@"window"][@"power_complete"] boolValue]);
        // A completed native activity interval can arrive after reconnect and a later checkpoint.
        REQUIRE([j recordActivity:@{@"ScreenOn" : @25} start:D(125) end:D(150) error:&error]);
        NSDictionary *delayed = IEBReadNativeJournal(dir, &error);
        REQUIRE([delayed[@"window"][@"end"] doubleValue] == 140);
        REQUIRE([delayed[@"activity_latest_end"] doubleValue] == 140);
        REQUIRE([delayed[@"global_metrics"][@"ScreenOn"] doubleValue] == 25);
        REQUIRE(![j recordPower:0 nativeTime:150 error:&error] && error);
        REQUIRE(![j recordActivity:@{
            @"BundleID" : @"app.test",
            @"ScreenOnTime" : @(-1)
        }
                             start:D(140)
                               end:D(150)
                             error:&error] &&
                error);
        REQUIRE([j recordPower:0 nativeTime:160.1 error:&error]);
        r = IEBReadNativeJournal(dir, &error);
        REQUIRE([r[@"window"][@"start"] doubleValue] == 160.1 && [r[@"app_count"] integerValue] == 0);
        REQUIRE([j recordGapAtNativeTime:170 error:&error]);
        REQUIRE([j recordPower:1 nativeTime:180 error:&error]);
        r = IEBReadNativeJournal(dir, &error);
        REQUIRE(![r[@"window"][@"power_complete"] boolValue]);
        REQUIRE([j recordPower:0 nativeTime:190 error:&error]);
        REQUIRE([j recordPower:1 nativeTime:200 error:&error]);
        j = nil;
        j = [[IEBNativeJournal alloc] initWithDirectory:dir epoch:@"second" nativeTime:50 error:&error];
        REQUIRE(j && !error);
        r = IEBReadNativeJournal(dir, &error);
        REQUIRE([r[@"window"][@"start"] doubleValue] == 190 && [r[@"window"][@"end"] doubleValue] == 200 &&
                [r[@"window"][@"power_complete"] boolValue]);
        REQUIRE([j recordPower:0 nativeTime:51 error:&error]);
        r = IEBReadNativeJournal(dir, &error);
        REQUIRE([r[@"window"][@"start"] doubleValue] == 190); // cold detach never invents a session
        REQUIRE([j recordPower:1 nativeTime:60 error:&error]);
        REQUIRE([j recordPower:0 nativeTime:70 error:&error]);
        REQUIRE([j recordActivity:@{@"ScreenOn" : @20} start:D(70) end:D(90) error:&error]);
        REQUIRE([j checkpointAtNativeTime:100 error:&error]);
        j = nil;
        REQUIRE(sqlite3_open(dbPath.fileSystemRepresentation, &edit) == SQLITE_OK);
        REQUIRE(sqlite3_exec(edit, "UPDATE meta SET checkpoint=60", NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(edit) == SQLITE_OK);
        REQUIRE(![[IEBNativeJournal alloc] initWithDirectory:dir epoch:@"third" nativeTime:10 error:&error] &&
                error);
        REQUIRE(sqlite3_open(dbPath.fileSystemRepresentation, &edit) == SQLITE_OK);
        REQUIRE(sqlite3_exec(edit, "UPDATE meta SET checkpoint=100", NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(edit) == SQLITE_OK);
        j = [[IEBNativeJournal alloc] initWithDirectory:dir epoch:@"third" nativeTime:10 error:&error];
        r = IEBReadNativeJournal(dir, &error);
        REQUIRE(r && ![r[@"window"][@"power_complete"] boolValue] &&
                [r[@"window"][@"end"] doubleValue] == 100);
        REQUIRE([r[@"window"][@"start"] doubleValue] == 70 &&
                [r[@"global_metrics"][@"ScreenOn"] doubleValue] == 20);
        j = nil;
        REQUIRE(sqlite3_open(dbPath.fileSystemRepresentation, &edit) == SQLITE_OK);
        REQUIRE(sqlite3_exec(edit,
                             "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<200000) "
                             "INSERT INTO events(kind,epoch,t,power) SELECT 'power','third',10,1 FROM n",
                             NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(edit) == SQLITE_OK);
        REQUIRE(![[IEBNativeJournal alloc] initWithDirectory:dir
                                                       epoch:@"oversized"
                                                  nativeTime:11
                                                       error:&error] &&
                error);
        struct stat sb;
        NSString *file = [dir stringByAppendingPathComponent:@"native-journal.sqlite"];
        REQUIRE(lstat(file.fileSystemRepresentation, &sb) == 0 && (sb.st_mode & 0777) == 0600);
        REQUIRE(chmod(dir.fileSystemRepresentation, 0755) == 0);
        REQUIRE(!IEBReadNativeJournal(dir, &error) && error);
        REQUIRE(chmod(dir.fileSystemRepresentation, 0700) == 0);
        REQUIRE([fm removeItemAtPath:dir error:NULL]);
        REQUIRE([fm createDirectoryAtPath:dir
              withIntermediateDirectories:NO
                               attributes:@{
                                   NSFilePosixPermissions : @0700
                               }
                                    error:NULL]);
        REQUIRE(symlink("/dev/null", file.fileSystemRepresentation) == 0);
        REQUIRE(![[IEBNativeJournal alloc] initWithDirectory:dir epoch:@"bad" nativeTime:10 error:&error] &&
                error);
        REQUIRE([fm removeItemAtPath:dir error:NULL]);
        puts("PASS native journal persistence, app allocation, source gaps and epochs");
        return 0;
    }
}
