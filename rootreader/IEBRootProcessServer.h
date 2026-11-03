#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
BOOL IEBRootProcessAuthenticate(xpc_connection_t peer);
void IEBRootProcessAcceptPeer(xpc_connection_t peer, BOOL (^authenticate)(xpc_connection_t),
                              NSDictionary * (^reader)(void));
