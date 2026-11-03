#import <Foundation/Foundation.h>
// Owns an unpredictable private temporary directory. Release or explicitly remove after sharing.
@interface IEBDiagnosticExport : NSObject
@property(nonatomic, readonly, copy) NSArray<NSURL *> *fileURLs;
- (instancetype)initWithJSON:(NSData *)json readableText:(NSString *)text error:(NSError **)error;
- (instancetype)initWithJSON:(NSData *)json
                readableText:(NSString *)text
                    language:(NSString *)language
                       error:(NSError **)error;
- (BOOL)removeTemporaryFiles:(NSError **)error;
@end
