#import "../Sources/Diagnostics/IEBDiagnosticExport.h"
#import <Foundation/Foundation.h>
#import <sys/stat.h>
#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Export FAIL %d\n", __LINE__);                                                   \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        IEBDiagnosticExport *export = [[IEBDiagnosticExport alloc]
            initWithJSON:[@"{\"schema\":1}" dataUsingEncoding:NSUTF8StringEncoding]
            readableText:@"דוח אבחון סוללה"
                   error:&error];
        C(export && !error && export.fileURLs.count == 2);
        NSString *preferred = [NSBundle.mainBundle.preferredLocalizations.firstObject lowercaseString];
        BOOL hebrew = [preferred hasPrefix:@"he"] || [preferred hasPrefix:@"iw"];
        C([export.fileURLs[0].lastPathComponent
            isEqual:hebrew ? @"IEB-Diagnostics-he.txt" : @"IEB-Diagnostics-en.txt"]);
        C([export.fileURLs[0].pathExtension isEqual:@"txt"] &&
          [export.fileURLs[1].pathExtension isEqual:@"json"]);
        NSString *directory = export.fileURLs[0].URLByDeletingLastPathComponent.path;
        struct stat sb;
        C(stat(directory.fileSystemRepresentation, &sb) == 0 && (sb.st_mode & 0777) == 0700);
        for (NSURL *url in export.fileURLs)
            C(stat(url.fileSystemRepresentation, &sb) == 0 && (sb.st_mode & 0777) == 0600);
        C([[NSString stringWithContentsOfURL:export.fileURLs[0] encoding:NSUTF8StringEncoding
                                       error:&error] isEqual:@"דוח אבחון סוללה"]);
        C([NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:export.fileURLs[1]]
                                          options:0
                                            error:&error]);
        C([export removeTemporaryFiles:&error] && ![NSFileManager.defaultManager fileExistsAtPath:directory]);
        C([export removeTemporaryFiles:&error]);
        @autoreleasepool {
            IEBDiagnosticExport *ephemeral =
                [[IEBDiagnosticExport alloc] initWithJSON:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                             readableText:@"בדיקה"
                                                    error:&error];
            directory = ephemeral.fileURLs[0].URLByDeletingLastPathComponent.path;
        }
        C(![NSFileManager.defaultManager fileExistsAtPath:directory]);
        C(![[IEBDiagnosticExport alloc] initWithJSON:nil readableText:nil error:&error] && error);
        for (NSString *language in @[ @"en", @"he", @"HE-il", @"iw", @"fr", @"../../he" ]) {
            IEBDiagnosticExport *localized =
                [[IEBDiagnosticExport alloc] initWithJSON:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                             readableText:@"Report"
                                                 language:language
                                                    error:&error];
            C(localized && !error);
            BOOL he = [@[ @"he", @"HE-il", @"iw" ] containsObject:language];
            C([localized.fileURLs[0].lastPathComponent
                isEqual:he ? @"IEB-Diagnostics-he.txt" : @"IEB-Diagnostics-en.txt"]);
            C([localized.fileURLs[1].lastPathComponent isEqual:@"IEB-Diagnostics.json"]);
            C([localized removeTemporaryFiles:&error] && !error);
        }
        puts("PASS TXT/JSON export files are readable, private and cleaned after release or cancellation");
        return 0;
    }
}
