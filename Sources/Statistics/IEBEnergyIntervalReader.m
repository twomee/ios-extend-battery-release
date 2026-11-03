#import "IEBEnergyIntervalReader.h"
#import <math.h>
#import <sqlite3.h>
#import <time.h>

static double MonotonicNow(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
        return INFINITY;
    return value.tv_sec + value.tv_nsec / 1e9;
}
static int Expired(void *context) { return MonotonicNow() > *(double *)context; }
static void ReadError(NSError **error, NSString *message) {
    if (error)
        *error = [NSError errorWithDomain:@"IEBEnergyIntervalReader"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
}
static NSDictionary *ReadEnergy(NSString *path, double start, double end, BOOL enrich, NSError **error) {
    if (error)
        *error = nil;
    if (![path isKindOfClass:[NSString class]] || !path.isAbsolutePath ||
        [path rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound ||
        !isfinite(start) || !isfinite(end) || start <= 0 || end <= start || end - start > 864000) {
        ReadError(error, @"Invalid database path or interval window");
        return nil;
    }
    sqlite3 *db = NULL;
    sqlite3_stmt *statement = NULL;
    NSDictionary *result = nil;
    NSString *failure = @"Cannot open read-only accounting source";
    BOOL transaction = NO;
    double deadline = MonotonicNow() + 5;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithObject:@NO
                                                                       forKey:@"coverage_verified"];
    NSArray *keys = @[
        @"ID", @"timestamp", @"StartOffset", @"EndOffset", @"Energy", @"CorrectionEnergy",
        @"TerminationRatio", @"NodeID", @"RootNodeID"
    ];
    int status;
    if (!isfinite(deadline)) {
        failure = @"Cannot establish accounting query deadline";
        goto done;
    }
    if (sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK)
        goto done;
    sqlite3_busy_timeout(db, 1000);
    sqlite3_progress_handler(db, 1000, Expired, &deadline);
    failure = @"Cannot begin consistent accounting snapshot";
    if (sqlite3_exec(db, "BEGIN", NULL, NULL, NULL) != SQLITE_OK)
        goto done;
    transaction = YES;
    // Invalid bounds cannot be assigned to any window: SQL NULL/coercion must
    // not hide them in WHERE or MIN/MAX and turn unreadable energy into zero.
    failure = @"Invalid or unsupported native interval bounds";
    if (sqlite3_prepare_v2(
            db,
            "SELECT 1 FROM PLAccountingOperator_EventInterval_EnergyEstimateEvents WHERE "
            "typeof(timestamp) NOT IN ('integer','real') OR timestamp<=0 OR "
            "typeof(StartOffset) NOT IN ('integer','real') OR "
            "typeof(EndOffset) NOT IN ('integer','real') OR EndOffset<StartOffset OR "
            "abs(timestamp)>1.7976931348623157e308 OR "
            "abs(StartOffset)>1.7976931348623157e308 OR abs(EndOffset)>1.7976931348623157e308 OR "
            "timestamp+StartOffset/1000.0<=0 OR "
            "abs(timestamp+StartOffset/1000.0)>1.7976931348623157e308 OR "
            "abs(timestamp+EndOffset/1000.0)>1.7976931348623157e308 LIMIT 1",
            -1, &statement, NULL) != SQLITE_OK)
        goto done;
    if (sqlite3_step(statement) != SQLITE_DONE)
        goto done;
    sqlite3_finalize(statement);
    statement = NULL;
    failure = @"Missing or unsupported native accounting schema";
    if (sqlite3_prepare_v2(db,
                           "SELECT MIN(timestamp+StartOffset/1000.0),MAX(timestamp+EndOffset/1000.0) "
                           "FROM PLAccountingOperator_EventInterval_EnergyEstimateEvents",
                           -1, &statement, NULL) != SQLITE_OK)
        goto done;
    failure = @"Cannot read native retention bounds";
    if (sqlite3_step(statement) != SQLITE_ROW)
        goto done;
    if (sqlite3_column_type(statement, 0) != SQLITE_NULL &&
        sqlite3_column_type(statement, 1) != SQLITE_NULL) {
        double first = sqlite3_column_double(statement, 0), last = sqlite3_column_double(statement, 1);
        if (!isfinite(first) || !isfinite(last) || first <= 0 || last < first)
            goto done;
        snapshot[@"retention_start"] = @(first);
        snapshot[@"retention_end"] = @(last);
    }
    sqlite3_finalize(statement);
    statement = NULL;
    failure = @"Missing or unsupported energy interval columns";
    if (sqlite3_prepare_v2(
            db,
            "SELECT "
            "ID,timestamp,StartOffset,EndOffset,Energy,CorrectionEnergy,TerminationRatio,NodeID,RootNodeID "
            "FROM PLAccountingOperator_EventInterval_EnergyEstimateEvents "
            "WHERE timestamp+EndOffset/1000.0 > ?1 AND timestamp+StartOffset/1000.0 < ?2 "
            "ORDER BY ID LIMIT 500001",
            -1, &statement, NULL) != SQLITE_OK)
        goto done;
    failure = @"Cannot bind accounting window";
    if (sqlite3_bind_double(statement, 1, start) != SQLITE_OK ||
        sqlite3_bind_double(statement, 2, end) != SQLITE_OK)
        goto done;
    failure = @"Invalid, oversized or interrupted accounting snapshot";
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        if (rows.count >= 500000)
            goto done;
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < (int)keys.count; i++) {
            int type = sqlite3_column_type(statement, i);
            if (type == SQLITE_INTEGER)
                row[keys[i]] = @(sqlite3_column_int64(statement, i));
            else if (type == SQLITE_FLOAT && isfinite(sqlite3_column_double(statement, i)))
                row[keys[i]] = @(sqlite3_column_double(statement, i));
            else
                goto done;
        }
        [rows addObject:row];
    }
    if (status != SQLITE_DONE)
        goto done;
    sqlite3_finalize(statement);
    statement = NULL;
    if (enrich) {
        failure = @"Invalid or unavailable native node-name source";
        NSMutableDictionary *names = [NSMutableDictionary new];
        if (sqlite3_prepare_v2(
                db, "SELECT ID,Name FROM PLAccountingOperator_EventNone_Nodes ORDER BY ID LIMIT 100001", -1,
                &statement, NULL) != SQLITE_OK)
            goto done;
        NSUInteger nodeCount = 0;
        while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
            if (++nodeCount > 100000 || sqlite3_column_type(statement, 0) != SQLITE_INTEGER ||
                sqlite3_column_int64(statement, 0) < 0 ||
                (sqlite3_column_type(statement, 1) != SQLITE_TEXT &&
                 sqlite3_column_type(statement, 1) != SQLITE_NULL) ||
                sqlite3_column_bytes(statement, 1) > 4096)
                goto done;
            if (sqlite3_column_type(statement, 1) == SQLITE_NULL || sqlite3_column_bytes(statement, 1) == 0)
                continue;
            NSString *name = [[NSString alloc] initWithBytes:sqlite3_column_text(statement, 1)
                                                      length:(NSUInteger)sqlite3_column_bytes(statement, 1)
                                                    encoding:NSUTF8StringEncoding];
            if (!name)
                goto done;
            names[@(sqlite3_column_int64(statement, 0))] = name;
        }
        if (status != SQLITE_DONE)
            goto done;
        sqlite3_finalize(statement);
        statement = NULL;
        snapshot[@"node_names"] = names;
    }
    failure = @"Cannot complete accounting snapshot";
    if (sqlite3_exec(db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK)
        goto done;
    transaction = NO;
    snapshot[@"rows"] = [rows copy];
    result = [snapshot copy];
done:
    if (statement)
        sqlite3_finalize(statement);
    if (transaction)
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
    if (db)
        sqlite3_close(db);
    if (!result)
        ReadError(error, failure);
    return result;
}

NSDictionary *IEBReadEnergyIntervals(NSString *path, double start, double end, NSError **error) {
    return ReadEnergy(path, start, end, NO, error);
}
static NSArray *ReadLevels(NSString *path, double start, double end, NSError **error) {
    if (error)
        *error = nil;
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath ||
        [path rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound ||
        !isfinite(start) || !isfinite(end) || start <= 0 || end <= start || end - start > 864000) {
        ReadError(error, @"Invalid battery-level window");
        return nil;
    }
    sqlite3 *db = NULL;
    sqlite3_stmt *statement = NULL;
    NSMutableArray *levels = [NSMutableArray new];
    NSArray *result = nil;
    double deadline = MonotonicNow() + 5;
    if (!isfinite(deadline) ||
        sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK)
        goto done;
    sqlite3_busy_timeout(db, 1000);
    sqlite3_progress_handler(db, 1000, Expired, &deadline);
    if (sqlite3_exec(db, "BEGIN", NULL, NULL, NULL) != SQLITE_OK)
        goto done;
    if (sqlite3_prepare_v2(db,
                           "SELECT 1 FROM PLBatteryAgent_EventBackward_Battery WHERE typeof(timestamp) NOT "
                           "IN ('integer','real') OR timestamp<=0 OR timestamp>1.7976931348623157e308 OR "
                           "typeof(Level) NOT IN ('integer','real') OR NOT(Level>=0 AND Level<=100) LIMIT 1",
                           -1, &statement, NULL) != SQLITE_OK ||
        sqlite3_step(statement) != SQLITE_DONE)
        goto done;
    sqlite3_finalize(statement);
    statement = NULL;
    if (sqlite3_prepare_v2(
            db,
            "SELECT timestamp,Level FROM PLBatteryAgent_EventBackward_Battery WHERE ID=(SELECT ID FROM "
            "PLBatteryAgent_EventBackward_Battery WHERE timestamp<?1 ORDER BY timestamp DESC,ID DESC LIMIT "
            "1) OR (timestamp>=?1 AND timestamp<=?2) ORDER BY timestamp,ID LIMIT 200001",
            -1, &statement, NULL) != SQLITE_OK ||
        sqlite3_bind_double(statement, 1, start) != SQLITE_OK ||
        sqlite3_bind_double(statement, 2, end) != SQLITE_OK)
        goto done;
    int status;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        if (levels.count >= 200000 || !isfinite(sqlite3_column_double(statement, 0)) ||
            !isfinite(sqlite3_column_double(statement, 1)))
            goto done;
        [levels addObject:@{
            @"time" : @(sqlite3_column_double(statement, 0)),
            @"level" : @(sqlite3_column_double(statement, 1))
        }];
    }
    if (status != SQLITE_DONE)
        goto done;
    sqlite3_finalize(statement);
    statement = NULL;
    if (sqlite3_exec(db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK)
        goto done;
    result = [levels copy];
done:
    if (statement)
        sqlite3_finalize(statement);
    if (db) {
        if (!sqlite3_get_autocommit(db))
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        sqlite3_close(db);
    }
    if (!result)
        ReadError(error, @"Invalid or unavailable native battery-level source");
    return result;
}
NSDictionary *IEBReadEnergyAndLevels(NSString *path, double start, double end, NSError **error) {
    if (error)
        *error = nil;
    NSError *energyError = nil, *levelError = nil;
    NSDictionary *energy = ReadEnergy(path, start, end, YES, &energyError);
    NSArray *levels = ReadLevels(path, start, end, &levelError);
    NSMutableDictionary *result = energy ? [energy mutableCopy]
                                         : [@{@"rows" : NSNull.null,
                                              @"node_names" : @{}} mutableCopy];
    result[@"levels"] = levels ?: @[];
    if (!energy)
        result[@"energy_error"] = energyError.localizedDescription ?: @"Native energy unavailable";
    if (!levels)
        result[@"levels_error"] = levelError.localizedDescription ?: @"Battery levels unavailable";
    return result;
}
