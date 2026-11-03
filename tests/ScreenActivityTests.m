#import "../Sources/Statistics/IEBScreenActivity.h"
#import <sqlite3.h>
#define CHECK(x)                                                                                             \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Screen activity FAIL %d\n", __LINE__);                                          \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSError *e = nil;
        NSArray *b = @[ @{@"start" : @100, @"end" : @110}, @{@"start" : @110, @"end" : @120} ];
        NSDictionary *r = IEBScreenActivity(@[
            @{@"time" : @90,
              @"active" : @1},
            @{@"time" : @105,
              @"active" : @0},
            @{@"time" : @115,
              @"active" : @1}
        ],
                                            100, 120, b, &e);
        CHECK(r && !e && [r[@"screen_on"] doubleValue] == 10);
        CHECK([r[@"buckets"][0][@"ScreenOn"] doubleValue] == 5 &&
              [r[@"buckets"][1][@"ScreenOn"] doubleValue] == 5);
        r = IEBScreenActivity(@[ @{@"time" : @90, @"active" : @1} ], 100, 120, b, &e);
        CHECK(r && [r[@"screen_on"] doubleValue] == 20);
        CHECK(!IEBScreenActivity(@[ @{@"time" : @105, @"active" : @1} ], 100, 120, b, &e) && e);
        CHECK(!IEBScreenActivity(@[ @{@"time" : @90, @"active" : @2} ], 100, 120, b, &e) && e);
        CHECK(!IEBScreenActivity(@[ @{@"time" : @95,
                                      @"active" : @1},
                                    @{@"time" : @90,
                                      @"active" : @0} ],
                                 100, 120, b, &e) &&
              e);
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        sqlite3 *db = NULL;
        CHECK(sqlite3_open(path.UTF8String, &db) == SQLITE_OK);
        CHECK(sqlite3_exec(
                  db,
                  "CREATE TABLE DisplayMetrics_DisplayState_1_2(ID INTEGER PRIMARY KEY,timestamp REAL,Active "
                  "INTEGER,Block TEXT); INSERT INTO DisplayMetrics_DisplayState_1_2 "
                  "VALUES(1,90,1,'ignored'),(2,105,0,'ignored'),(3,115,1,'ignored'),(4,130,0,'ignored');",
                  NULL, NULL, NULL) == SQLITE_OK);
        CHECK(sqlite3_close(db) == SQLITE_OK);
        r = IEBReadDisplayActivity(path, 100, 120, b, &e);
        CHECK(r && !e && [r[@"screen_on"] doubleValue] == 10);
        CHECK(sqlite3_open(path.UTF8String, &db) == SQLITE_OK);
        CHECK(sqlite3_exec(db, "INSERT INTO DisplayMetrics_DisplayState_1_2 VALUES(5,'corrupt',1,'ignored')",
                           NULL, NULL, NULL) == SQLITE_OK);
        CHECK(sqlite3_close(db) == SQLITE_OK);
        CHECK(!IEBReadDisplayActivity(path, 100, 120, b, &e) && e);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        puts("PASS display-state baseline, clipping, ongoing intervals and bounded readonly source");
        return 0;
    }
}
