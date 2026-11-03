#import "IEBRootProcessClient.h"
#import "IEBProcessSnapshot.h"
#import "IEBRootProcessProtocol.h"
#import <dlfcn.h>
#import <math.h>
static NSError *Error(NSString *reason) {
    return [NSError errorWithDomain:@"IEBRootProcessClient"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : reason}];
}
xpc_connection_t IEBCreateRootProcessConnection(void) {
    typedef xpc_connection_t (*Create)(const char *, dispatch_queue_t, uint64_t);
    Create create = (Create)dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
    return create ? create(IEBRootProcessServiceName, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                           XPC_CONNECTION_MACH_SERVICE_PRIVILEGED)
                  : nil;
}
NSDictionary *IEBRequestRootProcessConnection(xpc_connection_t connection, double timeout,
                                              BOOL (^verifyPeer)(xpc_connection_t), NSError **error) {
    if (error)
        *error = nil;
    if (!connection || !verifyPeer || !isfinite(timeout) || timeout <= 0 || timeout > 5) {
        if (error)
            *error = Error(@"connection-unavailable");
        return nil;
    }
    NSLock *lock = [NSLock new];
    dispatch_semaphore_t signal = dispatch_semaphore_create(0);
    __block BOOL finished = NO;
    __block NSDictionary *result = nil;
    __block NSError *failure = nil;
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        (void)event;
    });
    xpc_connection_activate(connection);
    xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(request, "version", 1);
    xpc_dictionary_set_string(request, "operation", "snapshot");
    xpc_connection_send_message_with_reply(
        connection, request, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(xpc_object_t reply) {
            [lock lock];
            if (finished) {
                [lock unlock];
                return;
            }
            if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY)
                failure = Error(@"service-unavailable");
            else if (!verifyPeer(connection))
                failure = Error(@"untrusted-peer");
            else {
                const char *status = xpc_dictionary_get_string(reply, "status");
                if (!status || strcmp(status, "ok") != 0)
                    failure =
                        Error(status && strcmp(status, "denied") == 0 ? @"caller-denied" : @"service-failed");
                else {
                    size_t size = 0;
                    const void *bytes = xpc_dictionary_get_data(reply, "payload", &size);
                    if (!bytes || !size || size > 2097152)
                        failure = Error(@"invalid-payload");
                    else
                        result =
                            IEBDecodeRootProcessSnapshot([NSData dataWithBytes:bytes length:size], &failure);
                }
            }
            finished = YES;
            [lock unlock];
            dispatch_semaphore_signal(signal);
        });
    long wait =
        dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    [lock lock];
    if (wait && !finished) {
        failure = Error(@"service-timeout");
        finished = YES;
    }
    NSDictionary *snapshot = result;
    NSError *readError = failure;
    [lock unlock];
    xpc_connection_cancel(connection);
    if (error)
        *error = readError;
    return snapshot;
}
BOOL IEBRootProcessPeerIsRoot(xpc_connection_t connection) {
    typedef pid_t (*PID)(xpc_connection_t);
    PID pid = (PID)dlsym(RTLD_DEFAULT, "xpc_connection_get_pid");
    return pid && xpc_connection_get_euid(connection) == 0 && pid(connection) > 1;
}
NSDictionary *IEBReadPreferredProcessSnapshot(void) {
    NSError *error = nil;
    NSDictionary *root = IEBRequestRootProcessConnection(
        IEBCreateRootProcessConnection(), 2,
        ^BOOL(xpc_connection_t peer) {
            return IEBRootProcessPeerIsRoot(peer);
        },
        &error);
    if (root && ![root[@"status"] isEqual:@"unavailable"])
        return root;
    NSMutableDictionary *fallback = [IEBReadProcessSnapshot() mutableCopy];
    fallback[@"reader_provider"] = @"mobile";
    fallback[@"reader_failure"] = error.localizedDescription ?: @"root-collector-unavailable";
    return fallback;
}
