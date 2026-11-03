#import "IEBSessionState.h"

// Directory must already exist, be owned by this user, and have mode 0700.
// Single writer; readers see either complete snapshot. A missing file is not an error.
IEBSessionState *IEBLoadSession(NSString *directory, NSError **error);
BOOL IEBSaveSession(IEBSessionState *state, NSString *directory, NSError **error);

BOOL IEBValidateSessionDirectory(NSString *directory, NSError **error);
