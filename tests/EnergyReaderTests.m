#import "../Sources/Statistics/IEBEnergyIntervalReader.h"
#import "../Sources/Statistics/IEBEnergyIntervals.h"
#import <sqlite3.h>
#define REQUIRE(c)                                                                                           \
    do {                                                                                                     \
        if (!(c)) {                                                                                          \
            fprintf(stderr, "Reader FAIL %d: %s\n", __LINE__, #c);                                           \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        sqlite3 *db = NULL;
        REQUIRE(sqlite3_open(path.UTF8String, &db) == SQLITE_OK);
        const char *schema =
            "CREATE TABLE PLAccountingOperator_EventInterval_EnergyEstimateEvents (ID INTEGER PRIMARY "
            "KEY,timestamp REAL,StartOffset INTEGER,EndOffset INTEGER,Energy INTEGER,CorrectionEnergy "
            "INTEGER,TerminationRatio INTEGER,NodeID INTEGER,RootNodeID INTEGER); INSERT INTO "
            "PLAccountingOperator_EventInterval_EnergyEstimateEvents VALUES "
            "(1,110,-10000,0,100,20,50,1,1),(2,120,-10000,0,200,0,100,1,1),(3,130,-10000,0,900,0,100,2,1);";
        REQUIRE(sqlite3_exec(db, schema, NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(db) == SQLITE_OK);
        NSError *error = nil;
        NSDictionary *snapshot = IEBReadEnergyIntervals(path, 105, 120, &error);
        REQUIRE(snapshot && !error);
        REQUIRE([snapshot[@"rows"] count] == 2);
        REQUIRE([snapshot[@"retention_start"] doubleValue] == 100);
        REQUIRE([snapshot[@"retention_end"] doubleValue] == 130);
        REQUIRE([snapshot[@"coverage_verified"] isEqual:@NO]);
        REQUIRE([IEBEnergyForWindow(snapshot[@"rows"], 105, 120, NULL)[@"estimated_native_units"]
                    doubleValue] == 230);
        REQUIRE(sqlite3_open(path.UTF8String, &db) == SQLITE_OK);
        REQUIRE(
            sqlite3_exec(
                db,
                "CREATE TABLE PLAccountingOperator_EventNone_Nodes(ID INTEGER PRIMARY KEY,Name TEXT); INSERT "
                "INTO PLAccountingOperator_EventNone_Nodes VALUES(1,'app.fixture'),(2,''); CREATE TABLE "
                "PLBatteryAgent_EventBackward_Battery(ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL); "
                "INSERT INTO PLBatteryAgent_EventBackward_Battery VALUES(1,100,80),(2,110,79),(3,120,78);",
                NULL, NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(db) == SQLITE_OK);
        NSDictionary *enriched = IEBReadEnergyAndLevels(path, 105, 120, &error);
        REQUIRE(enriched && !error && [enriched[@"node_names"][@1] isEqual:@"app.fixture"]);
        REQUIRE([enriched[@"levels"] count] == 3);
        REQUIRE(sqlite3_open(path.UTF8String, &db) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db, "UPDATE PLBatteryAgent_EventBackward_Battery SET Level=-1 WHERE ID=1", NULL,
                             NULL, NULL) == SQLITE_OK);
        NSDictionary *partial = IEBReadEnergyAndLevels(path, 105, 120, &error);
        REQUIRE(partial && [partial[@"rows"] count] == 2 && partial[@"levels_error"] &&
                [partial[@"levels"] count] == 0);
        REQUIRE(sqlite3_exec(db, "UPDATE PLBatteryAgent_EventBackward_Battery SET Level=80 WHERE ID=1", NULL,
                             NULL, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_close(db) == SQLITE_OK);
        // A read-only probe must leave all existing rows intact.
        REQUIRE(sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK);
        sqlite3_stmt *stmt = NULL;
        REQUIRE(sqlite3_prepare_v2(
                    db, "SELECT COUNT(*) FROM PLAccountingOperator_EventInterval_EnergyEstimateEvents", -1,
                    &stmt, NULL) == SQLITE_OK);
        REQUIRE(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) == 3);
        sqlite3_finalize(stmt);
        sqlite3_close(db);
        REQUIRE(sqlite3_open(path.UTF8String, &db) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
                             "INSERT INTO PLAccountingOperator_EventInterval_EnergyEstimateEvents "
                             "VALUES(4,110,NULL,0,100,0,100,1,1)",
                             NULL, NULL, NULL) == SQLITE_OK);
        sqlite3_close(db);
        error = nil;
        REQUIRE(IEBReadEnergyIntervals(path, 100, 120, &error) == nil && error);
        partial = IEBReadEnergyAndLevels(path, 100, 120, &error);
        REQUIRE(partial && partial[@"energy_error"] && [partial[@"levels"] count] == 3);
        REQUIRE(IEBReadEnergyIntervals(@"/does/not/exist/ieb-db", 100, 110, &error) == nil && error);
        REQUIRE(IEBReadEnergyIntervals(path, 120, 100, NULL) == nil);
        NSString *emptyPath = [path stringByAppendingString:@"-empty"];
        REQUIRE(sqlite3_open(emptyPath.UTF8String, &db) == SQLITE_OK);
        sqlite3_close(db);
        REQUIRE(IEBReadEnergyIntervals(emptyPath, 100, 110, &error) == nil && error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:emptyPath error:NULL];
        puts("PASS read-only interval snapshot and schema failures");
    }
    return 0;
}
