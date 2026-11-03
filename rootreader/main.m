#import "../Sources/Diagnostics/IEBProcessSnapshot.h"
#import "../Sources/Diagnostics/IEBRootProcessClient.h"
#import "../Sources/Diagnostics/IEBRootProcessProtocol.h"
#import "IEBRootProcessServer.h"
#import <dlfcn.h>
#import <unistd.h>
static xpc_connection_t listener;
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (geteuid() != 0) {
            fputs("Root process reader requires root execution.\n", stderr);
            return 77;
        }
        BOOL check = argc == 2 && strcmp(argv[1], "--check-service") == 0,
             selfTest = argc == 2 && strcmp(argv[1], "--self-test") == 0;
        if (argc != 1 && !check && !selfTest) {
            fputs("Unsupported root reader operation.\n", stderr);
            return 64;
        }
        NSLock *lock = [NSLock new];
        __block NSDictionary *cached = nil;
        __block double updated = 0;
        NSDictionary * (^reader)(void) = ^NSDictionary * {
            [lock lock];
            double now = NSProcessInfo.processInfo.systemUptime;
            if (!cached || now - updated >= 1) {
                cached = IEBReadProcessSnapshot();
                updated = now;
            }
            NSDictionary *result = cached;
            [lock unlock];
            return result;
        };
        if (!check) {
            dispatch_queue_t queue = dispatch_queue_create(
                "com.idonamaan.ieb.process-reader",
                dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
            if (selfTest)
                listener = xpc_connection_create(NULL, queue);
            else {
                typedef xpc_connection_t (*Create)(const char *, dispatch_queue_t, uint64_t);
                Create create = (Create)dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
                if (create)
                    listener = create(IEBRootProcessServiceName, queue, XPC_CONNECTION_MACH_SERVICE_LISTENER);
            }
            if (!listener) {
                fputs("Root process listener unavailable.\n", stderr);
                return 69;
            }
            xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
                if (xpc_get_type(peer) == XPC_TYPE_CONNECTION)
                    IEBRootProcessAcceptPeer(
                        peer,
                        ^BOOL(xpc_connection_t c) {
                            return IEBRootProcessAuthenticate(c);
                        },
                        reader);
                else if (peer == XPC_ERROR_CONNECTION_INVALID) {
                    fputs("Root process listener invalid.\n", stderr);
                    exit(69);
                }
            });
            xpc_connection_activate(listener);
        }
        if (check || selfTest) {
            xpc_connection_t peer = check
                                        ? IEBCreateRootProcessConnection()
                                        : xpc_connection_create_from_endpoint(xpc_endpoint_create(listener));
            NSError *error = nil;
            NSDictionary *snapshot = IEBRequestRootProcessConnection(
                peer, 2,
                ^BOOL(xpc_connection_t connection) {
                    return IEBRootProcessPeerIsRoot(connection);
                },
                &error);
            if (!snapshot) {
                fprintf(stderr, "Root process check failed: %s\n", error.localizedDescription.UTF8String);
                return 69;
            }
            printf("root_reader=1 enumerated=%lu readable=%lu denied=%lu\n",
                   [snapshot[@"enumerated_count"] unsignedLongValue],
                   (unsigned long)[snapshot[@"rows"] count],
                   [snapshot[@"permission_denied_count"] unsignedLongValue]);
            return [snapshot[@"status"] isEqual:@"unavailable"] ? 69 : 0;
        }
        dispatch_main();
    }
}
