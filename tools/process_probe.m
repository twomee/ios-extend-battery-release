// Read-only numeric feasibility report. Never export process identities or rows.
#import "../Sources/Diagnostics/IEBProcessAttribution.h"
#import "../Sources/Diagnostics/IEBProcessSnapshot.h"
#import "../Sources/Diagnostics/IEBRootProcessClient.h"
#import "../Sources/Presentation/IEBApplicationCatalog.h"
#import "../Sources/Statistics/IEBStatisticsModel.h"
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSDictionary *model = IEBLoadStatistics(@"/var/mobile/Library/IEBNativeCapture", nil, 0, 0, &error);
        if (!model) {
            puts("model_unavailable=1");
            return 20;
        }
        NSDictionary *catalog = IEBLoadApplicationCatalog([model[@"apps"] valueForKey:@"id"]);
        NSDictionary *snapshot = IEBReadPreferredProcessSnapshot();
        NSDictionary *joined = IEBProcessAttribution(model[@"apps"] ?: @[], catalog ?: @{}, snapshot, nil);
        NSUInteger energy = 0;
        for (NSDictionary *row in joined[@"processes"])
            energy += [row[@"energy_percent"] isKindOfClass:NSNumber.class];
        printf("root_provider=%d enumerated=%lu readable=%lu denied=%lu matched_sources=%lu "
               "matched_energy=%lu\n",
               [snapshot[@"reader_provider"] isEqual:@"root-service"],
               [snapshot[@"enumerated_count"] unsignedLongValue], (unsigned long)[snapshot[@"rows"] count],
               [snapshot[@"permission_denied_count"] unsignedLongValue],
               (unsigned long)[joined[@"sources"] count], (unsigned long)energy);
        return 0;
    }
}
