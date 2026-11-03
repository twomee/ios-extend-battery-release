#import "../Sources/Statistics/IEBEnergyIntervalReader.h"
#import "../Sources/Statistics/IEBEnergyIntervals.h"
#import "IEBProbeSupport.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSDictionary *window = argc == 4 ? IEBParseQueryWindow([NSString stringWithUTF8String:argv[2]],
                                                               [NSString stringWithUTF8String:argv[3]])
                                         : nil;
        if (!window) {
            fprintf(stderr, "Usage: ieb-accounting-probe DATABASE MONOTONIC_START MONOTONIC_END\n");
            return 64;
        }
        NSDictionary *version =
            [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
        if (![version[@"ProductVersion"] isEqual:@"17.1.1"] ||
            ![version[@"ProductBuildVersion"] isEqual:@"21B91"])
            return 21;
        double start = [window[@"start"] doubleValue], end = [window[@"end"] doubleValue];
        NSError *error = nil;
        NSDictionary *source =
            IEBReadEnergyIntervals([NSString stringWithUTF8String:argv[1]], start, end, &error);
        NSDictionary *energy = source ? IEBEnergyForWindow(source[@"rows"], start, end, &error) : nil;
        NSMutableDictionary *report = [@{
            @"schema_version" : @1,
            @"feature_ready" : @NO,
            @"source_coverage_verified" : @NO,
            @"clock_domain" : @"native-monotonic",
            @"window" : window
        } mutableCopy];
        int status = 22;
        if (energy) {
            report[@"energy"] = energy;
            report[@"retention_start"] = source[@"retention_start"] ?: (id)[NSNull null];
            report[@"retention_end"] = source[@"retention_end"] ?: (id)[NSNull null];
            NSMutableSet *nodes = [NSMutableSet set];
            for (NSDictionary *row in source[@"rows"])
                [nodes addObject:row[@"NodeID"]];
            report[@"source_node_count"] = @(nodes.count);
        } else {
            report[@"error"] = error.localizedDescription ?: @"Unavailable native interval source";
            status = 23;
        }
        NSData *json =
            [NSJSONSerialization dataWithJSONObject:report
                                            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                              error:NULL];
        if (!json)
            return 74;
        fwrite(json.bytes, 1, json.length, stdout);
        puts("");
        return status;
    }
}
