#import "IEBDiagnosticExport.h"
#import "../Localization/IEBLocalization.h"
#import <errno.h>
#import <stdlib.h>
#import <string.h>
@implementation IEBDiagnosticExport {
    NSString *_directory;
    BOOL _removed;
}
- (instancetype)initWithJSON:(NSData *)json readableText:(NSString *)text error:(NSError **)error {
    return [self initWithJSON:json readableText:text language:IEBCurrentLanguage() error:error];
}
- (instancetype)initWithJSON:(NSData *)json
                readableText:(NSString *)text
                    language:(NSString *)language
                       error:(NSError **)error {
    self = [super init];
    if (!self)
        return nil;
    if (error)
        *error = nil;
    NSData *readable = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!json.length || !readable.length) {
        if (error)
            *error = [NSError
                errorWithDomain:@"IEBDiagnosticExport"
                           code:1
                       userInfo:@{NSLocalizedDescriptionKey : @"Diagnostic report content unavailable"}];
        return nil;
    }
    NSString *template =
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"IEBDiagnosticExport-XXXXXX"];
    char *path = strdup(template.fileSystemRepresentation);
    if (!path || !mkdtemp(path)) {
        int failure = errno;
        free(path);
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:failure userInfo:nil];
        return nil;
    }
    _directory = [NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:strlen(path)];
    free(path);
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm setAttributes:@{NSFilePosixPermissions : @0700} ofItemAtPath:_directory error:error])
        return nil;
    NSURL *folder = [NSURL fileURLWithPath:_directory isDirectory:YES];
    NSString *resolved = IEBResolvedLanguage(language ? @[ language ] : NSLocale.preferredLanguages);
    NSArray *urls = @[
        [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"IEB-Diagnostics-%@.txt", resolved]],
        [folder URLByAppendingPathComponent:@"IEB-Diagnostics.json"]
    ];
    NSArray *contents = @[ readable, json ];
    for (NSUInteger i = 0; i < urls.count; i++) {
        NSURL *url = urls[i];
        if (![contents[i] writeToURL:url options:NSDataWritingWithoutOverwriting error:error] ||
            ![fm setAttributes:@{NSFilePosixPermissions : @0600} ofItemAtPath:url.path error:error])
            return nil;
    }
    _fileURLs = [urls copy];
    return self;
}
- (BOOL)removeTemporaryFiles:(NSError **)error {
    if (error)
        *error = nil;
    if (_removed || !_directory)
        return YES;
    NSError *failure = nil;
    BOOL removed = [NSFileManager.defaultManager removeItemAtPath:_directory error:&failure];
    if (!removed && !([failure.domain isEqual:NSCocoaErrorDomain] && failure.code == NSFileNoSuchFileError)) {
        if (error)
            *error = failure;
        return NO;
    }
    _removed = YES;
    return YES;
}
- (void)dealloc {
    NSError *error = nil;
    if (![self removeTemporaryFiles:&error])
        NSLog(@"IEB diagnostic temporary file cleanup failed.");
}
@end
