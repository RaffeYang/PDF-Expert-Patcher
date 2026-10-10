// tests/SidebarPatchTest.m — 注册假 RDAKButton 类，验证：identifier 含
// com.readdle.right-panel.close 的按钮进入窗口即自隐藏；其他按钮不受影响。
// 退出码 0=通过。
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#define CHECK(cond, msg) do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); exit(1); } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        // Register a fake RDAKButton under the exact runtime name the dylib
        // hooks (real app: plain ObjC class "RDAKButton" from RDAppKit).
        Class cls = objc_allocateClassPair([NSButton class], "RDAKButton", 0);
        objc_registerClassPair(cls);

        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 500)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

        NSView *close = [[cls alloc] initWithFrame:NSMakeRect(304, 10, 24, 24)];
        close.accessibilityIdentifier = @"com.readdle.right-panel.close";
        NSView *closeAlt = [[cls alloc] initWithFrame:NSMakeRect(280, 30, 24, 24)];
        closeAlt.identifier = @"com.readdle.right-panel.close"; // legacy store
        NSView *innocent = [[cls alloc] initWithFrame:NSMakeRect(10, 10, 60, 24)];
        innocent.accessibilityIdentifier = @"com.readdle.right-panel.more";
        [w.contentView addSubview:close];
        [w.contentView addSubview:closeAlt];
        [w.contentView addSubview:innocent];

        const char *dylib = argc > 1 ? argv[1] : "build/SidebarPatch.dylib";
        if (!dlopen(dylib, RTLD_NOW)) {
            fprintf(stderr, "FAIL: dlopen(%s): %s\n", dylib, dlerror());
            return 2;
        }

        // viewDidMoveToWindow fired during addSubview; run more passes to prove
        // idempotency (self-healing re-hide included).
        for (NSView *v in @[close, closeAlt, innocent]) [v viewDidMoveToWindow];
        [close viewDidMoveToWindow];
        close.hidden = NO;   // simulate AppKit re-show
        [close viewDidMoveToWindow];

        CHECK(close.hidden == YES, "close button hidden");
        CHECK(closeAlt.hidden == YES, "close button (legacy identifier store) hidden");
        CHECK(innocent.hidden == NO, "innocent 'more' button untouched");

        printf("ALL TESTS PASSED\n");
        return 0;
    }
}
