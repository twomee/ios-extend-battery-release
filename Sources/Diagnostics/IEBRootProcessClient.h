#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
// Bounded transport seam; production always verifies the root peer. Call off the UI thread.
NSDictionary *IEBRequestRootProcessConnection(xpc_connection_t connection, double timeout,
                                              BOOL (^verifyPeer)(xpc_connection_t), NSError **error);
xpc_connection_t IEBCreateRootProcessConnection(void);
BOOL IEBRootProcessPeerIsRoot(xpc_connection_t connection);
NSDictionary *IEBReadPreferredProcessSnapshot(void);
