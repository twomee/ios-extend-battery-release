#import <Foundation/Foundation.h>
#include <sys/types.h>
extern const char *IEBRootProcessServiceName;
BOOL IEBRootProcessCallerAllowed(uid_t uid, NSString *signingIdentifier, uint32_t codeFlags);
BOOL IEBRootProcessRequestValid(NSDictionary *request);
NSData *IEBEncodeRootProcessSnapshot(NSDictionary *snapshot, NSError **error);
NSDictionary *IEBDecodeRootProcessSnapshot(NSData *data, NSError **error);
