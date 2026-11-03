#import "IEBScreenActivity.h"
#import <math.h>
#import <sqlite3.h>
static id Fail(NSError **e, NSString *message) {
    if (e)
        *e = [NSError errorWithDomain:@"IEBScreenActivity"
                                 code:1
                             userInfo:@{NSLocalizedDescriptionKey : message}];
    return nil;
}
static BOOL Num(id v) {
    return [v isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)v) != CFBooleanGetTypeID() &&
           isfinite([v doubleValue]);
}
NSDictionary *IEBScreenActivity(NSArray *points, double start, double end, NSArray *buckets,
                                NSError **error) {
    if (error)
        *error = nil;
    if (![points isKindOfClass:NSArray.class] || !points.count || points.count > 20000 || !isfinite(start) ||
        !isfinite(end) || start <= 0 || end <= start || end - start > 864000 ||
        ![buckets isKindOfClass:NSArray.class] || buckets.count > 96)
        return Fail(error, @"Display state unavailable or invalid range");
    double previous = 0;
    for (id p in points) {
        if (![p isKindOfClass:NSDictionary.class] || !Num(p[@"time"]) || !Num(p[@"active"]) ||
            [p[@"time"] doubleValue] <= 0 || [p[@"time"] doubleValue] < previous ||
            [p[@"time"] doubleValue] > end ||
            ([p[@"active"] doubleValue] != 0 && [p[@"active"] doubleValue] != 1))
            return Fail(error, @"Invalid display state event");
        previous = [p[@"time"] doubleValue];
    }
    if ([points[0][@"time"] doubleValue] > start)
        return Fail(error, @"Missing initial display state");
    NSMutableArray *result = [NSMutableArray new];
    previous = start;
    for (id bucket in buckets) {
        if (![bucket isKindOfClass:NSDictionary.class] || !Num(bucket[@"start"]) || !Num(bucket[@"end"]) ||
            [bucket[@"start"] doubleValue] < previous ||
            [bucket[@"end"] doubleValue] <= [bucket[@"start"] doubleValue] ||
            [bucket[@"end"] doubleValue] > end)
            return Fail(error, @"Invalid display graph buckets");
        previous = [bucket[@"end"] doubleValue];
        NSMutableDictionary *copy = [bucket mutableCopy];
        copy[@"ScreenOn"] = @0;
        [result addObject:copy];
    }
    double total = 0;
    for (NSUInteger i = 0; i < points.count; i++) {
        if (![points[i][@"active"] boolValue])
            continue;
        double a = MAX(start, [points[i][@"time"] doubleValue]),
               b = i + 1 < points.count ? [points[i + 1][@"time"] doubleValue] : end;
        if (b <= a)
            continue;
        total += b - a;
        for (NSMutableDictionary *bucket in result) {
            double overlap = MIN(b, [bucket[@"end"] doubleValue]) - MAX(a, [bucket[@"start"] doubleValue]);
            if (overlap > 0)
                bucket[@"ScreenOn"] = @([bucket[@"ScreenOn"] doubleValue] + overlap);
        }
    }
    return @{@"screen_on" : @(total), @"buckets" : result, @"points" : points};
}
static int Deadline(void *context) { return NSProcessInfo.processInfo.systemUptime > *(double *)context; }
NSDictionary *IEBReadDisplayActivity(NSString *path, double start, double end, NSArray *buckets,
                                     NSError **error) {
    if (error)
        *error = nil;
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath || !isfinite(start) || !isfinite(end) ||
        start <= 0 || end <= start || end - start > 864000)
        return Fail(error, @"Invalid display source request");
    sqlite3 *db = NULL;
    sqlite3_stmt *stmt = NULL;
    NSDictionary *result = nil;
    NSMutableArray *points = [NSMutableArray new];
    if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                        NULL) != SQLITE_OK)
        goto done;
    sqlite3_busy_timeout(db, 100);
    double deadline = NSProcessInfo.processInfo.systemUptime + 2;
    sqlite3_progress_handler(db, 1000, Deadline, &deadline);
    if (sqlite3_exec(db, "BEGIN", NULL, NULL, NULL) != SQLITE_OK)
        goto done;
    if (sqlite3_prepare_v2(db,
                           "SELECT 1 FROM DisplayMetrics_DisplayState_1_2 WHERE typeof(timestamp) NOT IN "
                           "('integer','real') OR timestamp<=0 OR abs(timestamp)>1.7976931348623157e308 OR "
                           "typeof(Active)!='integer' OR Active NOT IN (0,1) LIMIT 1",
                           -1, &stmt, NULL) != SQLITE_OK)
        goto done;
    if (sqlite3_step(stmt) != SQLITE_DONE)
        goto done;
    sqlite3_finalize(stmt);
    stmt = NULL;
    const char *queries[] = {"SELECT timestamp,Active FROM DisplayMetrics_DisplayState_1_2 WHERE "
                             "timestamp<=?1 ORDER BY timestamp DESC,ID DESC LIMIT 1",
                             "SELECT timestamp,Active FROM DisplayMetrics_DisplayState_1_2 WHERE "
                             "timestamp>?1 AND timestamp<=?2 ORDER BY timestamp,ID LIMIT 20001"};
    for (int q = 0; q < 2; q++) {
        if (sqlite3_prepare_v2(db, queries[q], -1, &stmt, NULL) != SQLITE_OK)
            goto done;
        sqlite3_bind_double(stmt, 1, start);
        if (q == 1)
            sqlite3_bind_double(stmt, 2, end);
        int rc;
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            int type = sqlite3_column_type(stmt, 0), state = sqlite3_column_type(stmt, 1);
            if ((type != SQLITE_FLOAT && type != SQLITE_INTEGER) || state != SQLITE_INTEGER ||
                points.count >= 20000)
                goto done;
            [points addObject:@{
                @"time" : @(sqlite3_column_double(stmt, 0)),
                @"active" : @(sqlite3_column_int64(stmt, 1))
            }];
        }
        if (rc != SQLITE_DONE)
            goto done;
        sqlite3_finalize(stmt);
        stmt = NULL;
    }
    result = IEBScreenActivity(points, start, end, buckets, error);
    if (sqlite3_exec(db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK)
        result = nil;
done:
    if (stmt)
        sqlite3_finalize(stmt);
    if (db) {
        sqlite3_progress_handler(db, 0, NULL, NULL);
        sqlite3_close(db);
    }
    if (!result && (!error || !*error))
        Fail(error, @"Native display events unavailable");
    return result;
}
