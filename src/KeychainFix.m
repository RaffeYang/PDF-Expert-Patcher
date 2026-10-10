// src/KeychainFix.m — Infrastructure fix: restore login persistence for the
// ad-hoc re-signed app.
//
// Root cause: PDF Expert stores its account session in the Data Protection
// Keychain under access group "3L68KQB4HG.com.readdle.PDFExpert-Mac". That
// group's availability is vouched by the Apple-issued code signature via the
// application-identifier entitlement. After ad-hoc re-signing securityd does
// not honor the claim, so every SecItem read/write fails and the app asks for
// login on each launch.
//
// Compatibility: retain the original v1.3 routing policy across ALL images.
// Strip kSecUseDataProtectionKeychain / kSecAttrAccessGroup on every SecItem
// query. Reads/writes may omit or vary these attributes; filtering on their
// presence sent paired operations to different keychains in v1.3.1.
// Do not narrow this policy without real login/relaunch evidence.
//
// Kill switch: KEYCHAINFIX_DISABLE=1. Debug: KEYCHAINFIX_DEBUG=1.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import "fishhook.h"

static OSStatus (*real_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
static OSStatus (*real_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
static OSStatus (*real_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
static OSStatus (*real_SecItemDelete)(CFDictionaryRef query);

static void KFLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"[KeychainFix] %@", [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

static BOOL KFDebug(void) { return getenv("KEYCHAINFIX_DEBUG") != NULL; }
static BOOL KFDisabled(void) { return getenv("KEYCHAINFIX_DISABLE") != NULL; }

// Return a retained mutable copy, preserving v1.3's uniform routing for
// Add/CopyMatching/Update/Delete. Null is passed to the original API unchanged.
static CFMutableDictionaryRef KFSanitize(CFDictionaryRef dict) {
    if (!dict) return NULL;
    NSMutableDictionary *m = [[NSMutableDictionary alloc]
        initWithDictionary:(__bridge NSDictionary *)dict];
    [m removeObjectForKey:(__bridge id)kSecUseDataProtectionKeychain];
    [m removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    return (__bridge_retained CFMutableDictionaryRef)m;
}

// Diagnostic text deliberately contains no service/account/group values or data.
// Logging must not influence routing or return status.
static NSString *KFDiagnostic(NSString *operation, CFDictionaryRef dict, OSStatus rc) {
    NSDictionary *q = dict && CFGetTypeID(dict) == CFDictionaryGetTypeID()
        ? (__bridge NSDictionary *)dict : @{};
    id cls = q[(__bridge id)kSecClass];
    NSString *kind = [cls isEqual:(__bridge id)kSecClassGenericPassword] ? @"generic-password"
        : [cls isEqual:(__bridge id)kSecClassInternetPassword] ? @"internet-password" : @"other/absent";
    id dp = q[(__bridge id)kSecUseDataProtectionKeychain];
    NSString *routing = !dp ? @"absent" : [dp isEqual:@YES] ? @"true" : @"false/other";
    NSString *message = CFBridgingRelease(SecCopyErrorMessageString(rc, NULL));
    return [NSString stringWithFormat:@"%@ status=%d (%@) class=%@ service=%@ group=%@ dp=%@",
        operation, (int)rc, message ?: @"unknown", kind,
        q[(__bridge id)kSecAttrService] ? @"present" : @"absent",
        q[(__bridge id)kSecAttrAccessGroup] ? @"present" : @"absent", routing];
}

static OSStatus KF_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (!real_SecItemAdd) return errSecUnimplemented;
    CFMutableDictionaryRef sanitized = KFSanitize(attributes);
    OSStatus rc = real_SecItemAdd(sanitized, result);
    if (KFDebug()) KFLog(@"%@", KFDiagnostic(@"Add", attributes, rc));
    if (sanitized) CFRelease(sanitized);
    return rc;
}

static OSStatus KF_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!real_SecItemCopyMatching) return errSecUnimplemented;
    CFMutableDictionaryRef sanitized = KFSanitize(query);
    OSStatus rc = real_SecItemCopyMatching(sanitized, result);
    if (KFDebug()) KFLog(@"%@", KFDiagnostic(@"CopyMatching", query, rc));
    if (sanitized) CFRelease(sanitized);
    return rc;
}

static OSStatus KF_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    if (!real_SecItemUpdate) return errSecUnimplemented;
    CFMutableDictionaryRef q = KFSanitize(query);
    OSStatus rc = real_SecItemUpdate(q, attrs);
    if (KFDebug()) KFLog(@"%@", KFDiagnostic(@"Update", query, rc));
    if (q) CFRelease(q);
    return rc;
}

static OSStatus KF_SecItemDelete(CFDictionaryRef query) {
    if (!real_SecItemDelete) return errSecUnimplemented;
    CFMutableDictionaryRef q = KFSanitize(query);
    OSStatus rc = real_SecItemDelete(q);
    if (KFDebug()) KFLog(@"%@", KFDiagnostic(@"Delete", query, rc));
    if (q) CFRelease(q);
    return rc;
}

static void KFInstall(void) {
    struct rebinding rebindings[] = {
        { "SecItemAdd",           (void *)KF_SecItemAdd,           (void **)&real_SecItemAdd },
        { "SecItemCopyMatching",  (void *)KF_SecItemCopyMatching,  (void **)&real_SecItemCopyMatching },
        { "SecItemUpdate",        (void *)KF_SecItemUpdate,        (void **)&real_SecItemUpdate },
        { "SecItemDelete",        (void *)KF_SecItemDelete,        (void **)&real_SecItemDelete },
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    KFLog(@"fishhook rebind rc=%d%s", rc, KFDebug() ? " (debug on)" : "");
}

__attribute__((constructor)) static void KeychainFixMain(void) {
    @autoreleasepool { if (!KFDisabled()) KFInstall(); }
}
