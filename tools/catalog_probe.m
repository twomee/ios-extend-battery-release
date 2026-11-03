#import "../Sources/Presentation/IEBApplicationCatalog.h"
#import "../Sources/Statistics/IEBSourceGroups.h"
#import "../Sources/Statistics/IEBStatisticsModel.h"
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        double began = NSProcessInfo.processInfo.systemUptime;
        NSDictionary *model = IEBLoadStatistics(@"/var/mobile/Library/IEBNativeCapture", nil, 0, 0, &error);
        if (!model)
            return 20;
        double start = NSProcessInfo.processInfo.systemUptime;
        NSDictionary *catalog = IEBLoadApplicationCatalog([model[@"apps"] valueForKey:@"id"]);
        if (!catalog) {
            fprintf(stderr, "Application catalog unavailable\n");
            return 20;
        }
        NSDictionary *groups = IEBSourceGroups(model[@"apps"], catalog);
        NSUInteger icons = 0, nativeIcons = 0, internalApps = 0, unknownClassification = 0;
        for (NSDictionary *entry in catalog.allValues) {
            if ([entry[@"icon"] isKindOfClass:UIImage.class])
                icons++;
            nativeIcons += [entry[@"icon_is_native"] boolValue];
            internalApps += ![entry[@"user_facing"] boolValue];
            unknownClassification += ![entry[@"classification_available"] boolValue];
        }
        printf("applications=%lu system_processes=%lu icons=%lu native_icons=%lu source_seconds=%.3f "
               "catalog_seconds=%.3f internal_bundles=%lu unknown_classification=%lu\n",
               (unsigned long)[groups[@"applications"] count],
               (unsigned long)[groups[@"system_processes"] count], (unsigned long)icons,
               (unsigned long)nativeIcons, start - began, NSProcessInfo.processInfo.systemUptime - start,
               (unsigned long)internalApps, (unsigned long)unknownClassification);
        return 0;
    }
}
