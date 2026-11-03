#import "../Sources/Diagnostics/IEBProcessSnapshot.h"
#import "../Sources/Diagnostics/IEBRootProcessClient.h"
#import "../Sources/Diagnostics/IEBRootProcessProtocol.h"
#import "../rootreader/IEBRootProcessServer.h"

#define C(x)                                                                                                 \
    do {                                                                                                     \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Root transport FAIL %d\n", __LINE__);                                           \
            return 1;                                                                                        \
        }                                                                                                    \
    } while (0)
static NSMutableArray *listeners;
static xpc_connection_t Pair(BOOL auth, BOOL silent) {
    if (!listeners)
        listeners = [NSMutableArray new];
    dispatch_queue_t queue = dispatch_queue_create("ieb.test.rootserver", DISPATCH_QUEUE_SERIAL);
    xpc_connection_t listener = xpc_connection_create(NULL, queue);
    xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) != XPC_TYPE_CONNECTION)
            return;
        if (silent) {
            @synchronized(listeners) {
                [listeners addObject:peer];
            }
            xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
                if (xpc_get_type(event) == XPC_TYPE_DICTIONARY) {
                    @synchronized(listeners) {
                        [listeners addObject:event];
                    }
                }
            });
            xpc_connection_activate(peer);
        } else
            IEBRootProcessAcceptPeer(
                peer,
                ^BOOL(xpc_connection_t c) {
                    (void)c;
                    return auth;
                },
                ^NSDictionary * {
                    return IEBReadProcessSnapshot();
                });
    });
    xpc_connection_activate(listener);
    xpc_endpoint_t endpoint = xpc_endpoint_create(listener);
    xpc_connection_t connection = xpc_connection_create_from_endpoint(endpoint);
    @synchronized(listeners) {
        [listeners addObject:listener];
    }
    return connection;
}
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSDictionary *r = IEBRequestRootProcessConnection(
            Pair(YES, NO), 2,
            ^BOOL(xpc_connection_t peer) {
                (void)peer;
                return YES;
            },
            &error);
        if (!r)
            fprintf(stderr, "transport error %s\n", error.localizedDescription.UTF8String);
        C(r && !error && [r[@"reader_provider"] isEqual:@"root-service"] && [r[@"rows"] count] > 0);
        C(!IEBRequestRootProcessConnection(
              Pair(NO, NO), 1,
              ^BOOL(xpc_connection_t p) {
                  (void)p;
                  return YES;
              },
              &error) &&
          error);
        C(!IEBRequestRootProcessConnection(
              Pair(YES, NO), 1,
              ^BOOL(xpc_connection_t p) {
                  (void)p;
                  return NO;
              },
              &error) &&
          [error.localizedDescription isEqual:@"untrusted-peer"]);
        r = IEBRequestRootProcessConnection(
            Pair(YES, YES), 0.05,
            ^BOOL(xpc_connection_t p) {
                (void)p;
                return YES;
            },
            &error);
        C(!r && [error.localizedDescription isEqual:@"service-timeout"]);
        C(!IEBRequestRootProcessConnection(nil, 1, nil, &error) && error);
        puts("PASS XPC snapshot request/reply, denied caller, untrusted peer, bounded timeout");
        return 0;
    }
}
