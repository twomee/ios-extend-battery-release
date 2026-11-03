#import "IEBRootProcessServer.h"
#import "../Sources/Diagnostics/IEBRootProcessProtocol.h"
#import <dlfcn.h>
#import <mach/message.h>
BOOL IEBRootProcessAuthenticate(xpc_connection_t peer) {
    uid_t uid = xpc_connection_get_euid(peer);
    if (uid == 0)
        return YES;
    if (uid != 501)
        return NO;
    typedef void (*Audit)(xpc_connection_t, audit_token_t *);
    typedef CFTypeRef (*Create)(CFAllocatorRef, audit_token_t);
    typedef CFStringRef (*Identity)(CFTypeRef, CFErrorRef *);
    typedef uint32_t (*Flags)(CFTypeRef);
    static Audit audit;
    static Create create;
    static Identity identity;
    static Flags flags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *security =
            dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL);
        if (!security)
            return;
        audit = (Audit)dlsym(RTLD_DEFAULT, "xpc_connection_get_audit_token");
        create = (Create)dlsym(security, "SecTaskCreateWithAuditToken");
        identity = (Identity)dlsym(security, "SecTaskCopySigningIdentifier");
        flags = (Flags)dlsym(security, "SecTaskGetCodeSignStatus");
    });
    if (!audit || !create || !identity || !flags)
        return NO;
    audit_token_t token = {0};
    audit(peer, &token);
    CFTypeRef task = create(kCFAllocatorDefault, token);
    if (!task)
        return NO;
    CFErrorRef error = NULL;
    CFStringRef identifier = identity(task, &error);
    uint32_t status = flags(task);
    BOOL allowed = IEBRootProcessCallerAllowed(uid, (__bridge NSString *)identifier, status);
    if (error)
        CFRelease(error);
    if (identifier)
        CFRelease(identifier);
    CFRelease(task);
    return allowed;
}
void IEBRootProcessAcceptPeer(xpc_connection_t peer, BOOL (^authenticate)(xpc_connection_t),
                              NSDictionary * (^reader)(void)) {
    static NSMutableSet *connections;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        connections = [NSMutableSet new];
    });
    @synchronized(connections) {
        if (connections.count >= 16 || !authenticate(peer)) {
            xpc_connection_cancel(peer);
            return;
        }
        [connections addObject:peer];
    }
    __weak xpc_connection_t weakPeer = peer;
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
        @autoreleasepool {
            xpc_connection_t connection = weakPeer;
            if (!connection)
                return;
            if (event == XPC_ERROR_CONNECTION_INVALID) {
                @synchronized(connections) {
                    [connections removeObject:connection];
                }
                return;
            }
            if (xpc_get_type(event) != XPC_TYPE_DICTIONARY)
                return;
            xpc_object_t reply = xpc_dictionary_create_reply(event);
            if (!reply)
                return;
            const char *status = "denied";
            NSData *payload = nil;
            if (authenticate(connection)) {
                xpc_object_t version = xpc_dictionary_get_value(event, "version"),
                             operation = xpc_dictionary_get_value(event, "operation");
                BOOL types = version && operation && xpc_get_type(version) == XPC_TYPE_UINT64 &&
                             xpc_get_type(operation) == XPC_TYPE_STRING;
                BOOL valid =
                    types && xpc_dictionary_get_count(event) == 2 && xpc_string_get_length(operation) == 8 &&
                    IEBRootProcessRequestValid(@{
                        @"version" : @(xpc_uint64_get_value(version)),
                        @"operation" : [NSString stringWithUTF8String:xpc_string_get_string_ptr(operation)]
                    });
                status = "invalid-request";
                if (valid) {
                    NSError *error = nil;
                    payload = IEBEncodeRootProcessSnapshot(reader(), &error);
                    status = payload && !error ? "ok" : "collector-failed";
                }
            }
            xpc_dictionary_set_string(reply, "status", status);
            if (payload)
                xpc_dictionary_set_data(reply, "payload", payload.bytes, payload.length);
            xpc_connection_send_message(connection, reply);
        }
    });
    xpc_connection_activate(peer);
}
