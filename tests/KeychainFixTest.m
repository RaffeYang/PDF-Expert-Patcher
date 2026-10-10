#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "fishhook.h"
static int installs;
static CFDictionaryRef seen;
static CFDictionaryRef updateSeen;
static OSStatus FakeAdd(CFDictionaryRef q, CFTypeRef *out) { seen = CFRetain(q); return -25299; }
static OSStatus FakeCopy(CFDictionaryRef q, CFTypeRef *out) { seen = CFRetain(q); return -25300; }
static OSStatus FakeUpdate(CFDictionaryRef q, CFDictionaryRef attrs) { seen = CFRetain(q); updateSeen = attrs; return -50; }
static OSStatus FakeDelete(CFDictionaryRef q) { seen = CFRetain(q); return -25300; }
int rebind_symbols(struct rebinding rebindings[], size_t count) {
    installs++;
    for (size_t i = 0; i < count; i++) {
        void *p = NULL;
        if (!strcmp(rebindings[i].name, "SecItemAdd")) p = (void *)FakeAdd;
        if (!strcmp(rebindings[i].name, "SecItemCopyMatching")) p = (void *)FakeCopy;
        if (!strcmp(rebindings[i].name, "SecItemUpdate")) p = (void *)FakeUpdate;
        if (!strcmp(rebindings[i].name, "SecItemDelete")) p = (void *)FakeDelete;
        *rebindings[i].replaced = p;
    }
    return 0;
}
#import "../src/KeychainFix.m"
#define CHECK(c, m) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", m); return 1; } } while (0)
int main(void) {
    @autoreleasepool {
        if (getenv("KEYCHAINFIX_DISABLE")) {
            CHECK(installs == 0, "disabled constructor must not rebind symbols");
            puts("KEYCHAIN DISABLE TEST PASSED");
            return 0;
        }
        CHECK(installs == 1, "constructor installs once");
        real_SecItemAdd = NULL;
        CHECK(KF_SecItemAdd(NULL, NULL) == errSecUnimplemented, "unresolved original fails safely");
        real_SecItemAdd = FakeAdd;
        NSDictionary *target = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecUseDataProtectionKeychain: @YES,
            (__bridge id)kSecAttrAccessGroup: @"3L68KQB4HG.com.readdle.PDFExpert-Mac",
            (__bridge id)kSecAttrService: @"test-service",
            (__bridge id)kSecAttrAccount: @"test-sensitive-account",
            (__bridge id)kSecValueData: [@"test-sensitive-value" dataUsingEncoding:NSUTF8StringEncoding]};
        NSMutableDictionary *otherGroup = [target mutableCopy];
        otherGroup[(__bridge id)kSecAttrAccessGroup] = @"another.group";
        NSMutableDictionary *noGroup = [target mutableCopy];
        [noGroup removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        NSMutableDictionary *otherClass = [target mutableCopy];
        otherClass[(__bridge id)kSecClass] = (__bridge id)kSecClassInternetPassword;
        NSMutableDictionary *noDP = [target mutableCopy];
        noDP[(__bridge id)kSecUseDataProtectionKeychain] = @NO;
        NSMutableDictionary *noService = [target mutableCopy];
        [noService removeObjectForKey:(__bridge id)kSecAttrService];
        for (NSDictionary *query in @[target, otherGroup, noGroup, otherClass, noDP, noService]) {
            CFDictionaryRef q = (__bridge CFDictionaryRef)query;
            NSDictionary *attrs = @{(__bridge id)kSecValueData: [NSData data]};
            for (int op = 0; op < 4; op++) {
                OSStatus rc = 0;
                if (op == 0) rc = KF_SecItemAdd(q, NULL);
                if (op == 1) rc = KF_SecItemCopyMatching(q, NULL);
                if (op == 2) rc = KF_SecItemUpdate(q, (__bridge CFDictionaryRef)attrs);
                if (op == 3) rc = KF_SecItemDelete(q);
                CHECK(rc == (op == 0 ? -25299 : op == 2 ? -50 : -25300), "status propagated");
                NSDictionary *actual = (__bridge NSDictionary *)seen;
                NSMutableDictionary *expected = [query mutableCopy];
                [expected removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
                [expected removeObjectForKey:(__bridge id)kSecUseDataProtectionKeychain];
                CHECK([actual isEqual:expected], "v1.3 compatible routing for every query shape");
                if (op == 2) CHECK(updateSeen == (__bridge CFDictionaryRef)attrs, "update values untouched");
                CFRelease(seen);
            }
        }
        // Write and read often have different routing attributes. Both must
        // converge on the same login-keychain query, even without accessGroup.
        KF_SecItemAdd((__bridge CFDictionaryRef)target, NULL);
        NSDictionary *written = [(__bridge NSDictionary *)seen copy];
        CFRelease(seen);
        KF_SecItemCopyMatching((__bridge CFDictionaryRef)noGroup, NULL);
        CHECK([written isEqual:(__bridge NSDictionary *)seen], "asymmetric write/read route identically");
        CFRelease(seen);
        NSString *diagnostic = KFDiagnostic(@"CopyMatching", (__bridge CFDictionaryRef)target, errSecItemNotFound);
        CHECK([diagnostic containsString:@"CopyMatching"] && [diagnostic containsString:@"-25300"], "diagnostic operation and status");
        CHECK(![diagnostic containsString:@"test-service"] && ![diagnostic containsString:@"3L68KQB4HG"] &&
              ![diagnostic containsString:@"test-sensitive-account"] && ![diagnostic containsString:@"test-sensitive-value"], "diagnostic does not expose identifiers");
        CHECK([diagnostic containsString:@"service=present"] && [diagnostic containsString:@"group=present"], "diagnostic query shape only");
        CHECK(target[(__bridge id)kSecAttrAccessGroup] != nil, "input dictionary unmodified");
        puts("KEYCHAIN ROUTING TESTS PASSED");
    }
    return 0;
}
