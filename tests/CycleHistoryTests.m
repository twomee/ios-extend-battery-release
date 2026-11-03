#import "../Sources/Statistics/IEBCycleHistory.h"
#import "../Sources/Statistics/IEBNativeJournal.h"
#import <sqlite3.h>
#import <sys/stat.h>
#define REQUIRE(...)                                                                                         \
    do {                                                                                                     \
        if (!(__VA_ARGS__)) {                                                                                \
            fprintf(stderr, "History FAIL %d: %s\n", __LINE__, #__VA_ARGS__);                                \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSDate *D(double x) { return [NSDate dateWithTimeIntervalSince1970:x]; }
static BOOL Edit(NSString *dir, const char *sql) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open(
        [[dir stringByAppendingPathComponent:@"native-journal.sqlite"] fileSystemRepresentation], &db);
    if (rc == SQLITE_OK)
        rc = sqlite3_exec(db, sql, NULL, NULL, NULL);
    if (db)
        sqlite3_close(db);
    return rc == SQLITE_OK;
}
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        REQUIRE([NSFileManager.defaultManager createDirectoryAtPath:dir
                                        withIntermediateDirectories:NO
                                                         attributes:@{
                                                             NSFilePosixPermissions : @0700
                                                         }
                                                              error:&error]);
        IEBNativeJournal *j = [[IEBNativeJournal alloc] initWithDirectory:dir
                                                                    epoch:@"first"
                                                               nativeTime:100
                                                                    error:&error];
        REQUIRE(j && [j recordPower:1 nativeTime:100 error:&error]);
        REQUIRE([j recordPower:0 nativeTime:110 error:&error]);
        REQUIRE(!IEBSummarizeClosedCycle(IEBReadNativeJournal(dir, &error), &error) && !error);
        REQUIRE([j recordActivity:@{@"ScreenOn" : @15} start:D(110) end:D(130) error:&error]);
        REQUIRE([j recordActivity:@{
            @"BundleID" : @"private.app.identity",
            @"ScreenOnTime" : @8
        }
                            start:D(110)
                              end:D(130)
                            error:&error]);
        REQUIRE([j recordPower:1 nativeTime:140 error:&error]);
        NSDictionary *summary = IEBSummarizeClosedCycle(IEBReadNativeJournal(dir, &error), &error);
        REQUIRE(summary && !error && [summary[@"duration"] isEqual:@30]);
        REQUIRE([summary[@"screen_on"] isEqual:@15] && summary[@"screen_off"] == NSNull.null);
        REQUIRE([summary[@"activity_pending_seconds"] isEqual:@10]);
        NSSet *keys = [NSSet setWithArray:@[
            @"id", @"start", @"end", @"duration", @"screen_on", @"screen_off", @"activity_pending_seconds",
            @"power_complete"
        ]];
        REQUIRE([[NSSet setWithArray:summary.allKeys] isEqual:keys]);
        REQUIRE(Edit(dir, "ALTER TABLE cycle_history RENAME TO legacy_hidden"));
        REQUIRE([IEBReadNativeCycleHistory(dir, &error) count] == 1 && !error);
        REQUIRE(Edit(dir, "ALTER TABLE legacy_hidden RENAME TO cycle_history"));
        NSArray *history = IEBReadNativeCycleHistory(dir, &error);
        REQUIRE(history.count == 1 && !error && [history[0] isEqual:summary]);
        // Pruning must archive without any Settings read being needed.
        REQUIRE([j recordPower:0 nativeTime:150 error:&error]);
        history = IEBReadNativeCycleHistory(dir, &error);
        REQUIRE(history.count == 1 && [history[0] isEqual:summary]);
        REQUIRE([j checkpointAtNativeTime:151 error:&error]);
        REQUIRE([IEBReadNativeJournal(dir, &error)[@"app_count"] isEqual:@0]);
        for (int i = 0; i < 23; i++) {
            REQUIRE([j recordPower:1 nativeTime:160 + i * 20 error:&error]);
            if (i == 0) {
                REQUIRE(Edit(
                    dir, "INSERT INTO "
                         "cycle_history(cycle_id,start,end,duration,screen_on,screen_off,activity_pending_"
                         "seconds,power_complete) VALUES('5:first:150',150,160,10,NULL,NULL,10,1)"));
                REQUIRE([IEBReadNativeCycleHistory(dir, &error) count] == 2 && !error);
            }
            REQUIRE([j recordPower:0 nativeTime:170 + i * 20 error:&error]);
        }
        history = IEBReadNativeCycleHistory(dir, &error);
        REQUIRE(history.count == 20 && !error);
        REQUIRE([history[0][@"start"] isEqual:@590]);
        // Epoch resets cannot order native dates globally, and cold starts never invent cycles.
        j = nil;
        j = [[IEBNativeJournal alloc] initWithDirectory:dir epoch:@"second" nativeTime:10 error:&error];
        REQUIRE(j && [j recordPower:1 nativeTime:10 error:&error]);
        REQUIRE([j recordPower:0 nativeTime:20 error:&error]);
        REQUIRE([j checkpointAtNativeTime:30 error:&error]);
        j = nil;
        j = [[IEBNativeJournal alloc] initWithDirectory:dir epoch:@"third" nativeTime:5 error:&error];
        REQUIRE(j);
        history = IEBReadNativeCycleHistory(dir, &error);
        REQUIRE(history.count == 20 && [history[0][@"start"] isEqual:@20] &&
                [history[0][@"end"] isEqual:@30]);
        REQUIRE(![history[0][@"power_complete"] boolValue]);
        REQUIRE([j recordPower:1 nativeTime:5 error:&error]);
        REQUIRE([j recordPower:0 nativeTime:6 error:&error]);
        history = IEBReadNativeCycleHistory(dir, &error);
        REQUIRE(history.count == 20 && [history[0][@"start"] isEqual:@20]);
        NSDictionary *unknown = IEBCompareCycleSummaries(summary, @{});
        REQUIRE(unknown[@"duration_delta"] == NSNull.null &&
                unknown[@"energy_per_hour_delta"] == NSNull.null);
        NSMutableDictionary *a = [summary mutableCopy], *b = [summary mutableCopy];
        a[@"duration"] = @3600;
        b[@"duration"] = @7200;
        a[@"energy_total"] = @100;
        b[@"energy_total"] = @100;
        a[@"energy_per_hour"] = @100;
        b[@"energy_per_hour"] = @50;
        a[@"energy_coverage_known"] = @YES;
        b[@"energy_coverage_known"] = @YES;
        a[@"energy_partial"] = @NO;
        b[@"energy_partial"] = @NO;
        REQUIRE([IEBCompareCycleSummaries(a, b)[@"energy_per_hour_delta"] isEqual:@50]);
        REQUIRE([IEBCompareCycleSummaries(a, b)[@"energy_rate_relative_percent"] isEqual:@100]);
        REQUIRE([IEBCompareCycleSummaries(b, a)[@"energy_rate_relative_percent"] isEqual:@(-50)]);
        REQUIRE([IEBCompareCycleSummaries(a, a)[@"energy_rate_relative_percent"] isEqual:@0]);
        NSMutableDictionary *zero = [b mutableCopy];
        zero[@"energy_total"] = @0;
        zero[@"energy_per_hour"] = @0;
        REQUIRE(IEBCompareCycleSummaries(a, zero)[@"energy_rate_relative_percent"] == NSNull.null);
        REQUIRE([IEBCompareCycleSummaries(zero, a)[@"energy_rate_relative_percent"] isEqual:@(-100)]);
        REQUIRE(unknown[@"energy_rate_relative_percent"] == NSNull.null);
        NSMutableDictionary *shortCycle = [a mutableCopy];
        shortCycle[@"duration"] = @19.39;
        shortCycle[@"energy_total"] = @([shortCycle[@"energy_per_hour"] doubleValue] * 19.39 / 3600);
        REQUIRE(IEBCompareCycleSummaries(shortCycle, b)[@"energy_rate_relative_percent"] == NSNull.null);
        REQUIRE(IEBCompareCycleSummaries(b, shortCycle)[@"energy_rate_relative_percent"] == NSNull.null);
        shortCycle[@"duration"] = @60;
        shortCycle[@"energy_total"] = @([shortCycle[@"energy_per_hour"] doubleValue] / 60);
        REQUIRE([IEBCompareCycleSummaries(shortCycle, b)[@"energy_rate_relative_percent"] isEqual:@100]);
        NSMutableDictionary *large = [a mutableCopy], *tiny = [a mutableCopy];
        large[@"energy_total"] = @1e308;
        large[@"energy_per_hour"] = @1e308;
        tiny[@"energy_total"] = @1e-308;
        tiny[@"energy_per_hour"] = @1e-308;
        REQUIRE(IEBCompareCycleSummaries(large, tiny)[@"energy_rate_relative_percent"] == NSNull.null);
        b[@"energy_per_hour"] = @999;
        REQUIRE(![IEBCompareCycleSummaries(a, b)[@"comparable_energy"] boolValue]);
        b[@"energy_per_hour"] = @50;
        b[@"energy_partial"] = @YES;
        REQUIRE(IEBCompareCycleSummaries(a, b)[@"energy_rate_relative_percent"] == NSNull.null);
        REQUIRE(![IEBCompareCycleSummaries(a, b)[@"comparable_energy"] boolValue]);
        b[@"energy_partial"] = @NO;
        b[@"power_complete"] = @NO;
        REQUIRE(![IEBCompareCycleSummaries(a, b)[@"comparable_energy"] boolValue]);
        NSDictionary *unavailable = IEBLoadHistoricalCycle(summary, @"/nonexistent/history.sqlite", &error);
        REQUIRE(unavailable && [unavailable[@"id"] isEqual:summary[@"id"]] &&
                unavailable[@"energy_total"] == NSNull.null &&
                ![unavailable[@"energy_coverage_known"] boolValue]);
        REQUIRE(unavailable[@"energy_error"] != NSNull.null);
        NSString *native = [dir stringByAppendingPathComponent:@"energy.sqlite"];
        sqlite3 *nativeDB = NULL;
        REQUIRE(sqlite3_open(native.fileSystemRepresentation, &nativeDB) == SQLITE_OK);
        REQUIRE(
            sqlite3_exec(
                nativeDB,
                "CREATE TABLE PLAccountingOperator_EventInterval_EnergyEstimateEvents(ID INTEGER PRIMARY "
                "KEY,timestamp REAL,StartOffset INTEGER,EndOffset INTEGER,Energy INTEGER,CorrectionEnergy "
                "INTEGER,TerminationRatio INTEGER,NodeID INTEGER,RootNodeID INTEGER);"
                "INSERT INTO PLAccountingOperator_EventInterval_EnergyEstimateEvents "
                "VALUES(1,140,-30000,0,30,0,100,1,1);"
                "CREATE TABLE PLAccountingOperator_EventNone_Nodes(ID INTEGER PRIMARY KEY,Name TEXT);"
                "CREATE TABLE PLBatteryAgent_EventBackward_Battery(ID INTEGER PRIMARY KEY,timestamp "
                "REAL,Level REAL);"
                "CREATE TABLE DisplayMetrics_DisplayState_1_2(ID INTEGER PRIMARY KEY,timestamp REAL,Active "
                "INTEGER);"
                "INSERT INTO DisplayMetrics_DisplayState_1_2 VALUES(1,100,1),(2,120,0);",
                NULL, NULL, NULL) == SQLITE_OK);
        NSDictionary *enriched = IEBLoadHistoricalCycle(summary, native, &error);
        REQUIRE(enriched && !error && [enriched[@"energy_total"] isEqual:@30] &&
                [enriched[@"energy_per_hour"] isEqual:@3600]);
        REQUIRE([enriched[@"screen_on"] isEqual:@10] && [enriched[@"energy_coverage_known"] boolValue] &&
                ![enriched[@"energy_partial"] boolValue]);
        REQUIRE(sqlite3_exec(
                    nativeDB,
                    "UPDATE PLAccountingOperator_EventInterval_EnergyEstimateEvents SET StartOffset=-20000",
                    NULL, NULL, NULL) == SQLITE_OK);
        enriched = IEBLoadHistoricalCycle(summary, native, &error);
        REQUIRE(enriched[@"energy_per_hour"] == NSNull.null && [enriched[@"energy_partial"] boolValue]);
        REQUIRE([enriched[@"screen_on"] isEqual:@10]);
        REQUIRE(sqlite3_close(nativeDB) == SQLITE_OK);
        REQUIRE(Edit(
            dir,
            "INSERT INTO cycle_history(cycle_id,start,end,duration,activity_pending_seconds,power_complete) "
            "VALUES('overflow',1,2,1,0,1)"));
        REQUIRE(!IEBReadNativeCycleHistory(dir, &error) && error);
        REQUIRE(Edit(dir, "DELETE FROM cycle_history WHERE cycle_id='overflow'"));
        // Reader rejects unsafe metadata and corrupted archive instead of fabricating zeroes.
        REQUIRE(
            chmod([[dir stringByAppendingPathComponent:@"native-journal.sqlite"] fileSystemRepresentation],
                  0644) == 0);
        REQUIRE(!IEBReadNativeCycleHistory(dir, &error) && error);
        REQUIRE(
            chmod([[dir stringByAppendingPathComponent:@"native-journal.sqlite"] fileSystemRepresentation],
                  0600) == 0);
        REQUIRE(Edit(dir, "UPDATE cycle_history SET duration=-1"));
        REQUIRE(!IEBReadNativeCycleHistory(dir, &error) && error);
        REQUIRE([j recordPower:1 nativeTime:7 error:&error]);
        REQUIRE(![j recordPower:0 nativeTime:8 error:&error] && error);
        REQUIRE(![j recordPower:0 nativeTime:8 error:NULL]);
        REQUIRE([IEBReadNativeJournal(dir, &error)[@"window"][@"start"] isEqual:@6]);
        j = nil;
        REQUIRE([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
        puts("PASS closed-cycle summaries, atomic bounded archive, epochs and guarded comparison");
        return 0;
    }
}
