// tests/ToolbarPatchTest.m — 注册假 RDAKButton 类，验证：AI/Translate 工具栏
// 入口按钮（identifier 精确匹配）进入窗口即隐藏；其他工具栏按钮不受影响。
// 退出码 0=通过。
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#define CHECK(cond, msg) do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); exit(1); } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        Class cls = objc_allocateClassPair([NSButton class], "RDAKButton", 0);
        objc_registerClassPair(cls);

        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 80)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

        NSView *ai = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 34, 32)];
        ai.accessibilityIdentifier = @"com.readdle.toolbar.main.chat";
        NSView *tr = [[cls alloc] initWithFrame:NSMakeRect(40, 0, 34, 32)];
        tr.accessibilityIdentifier = @"com.readdle.toolbar.main.translate";
        NSView *share = [[cls alloc] initWithFrame:NSMakeRect(80, 0, 34, 32)];
        share.accessibilityIdentifier = @"com.readdle.toolbar.main.share";
        NSView *redact = [[cls alloc] initWithFrame:NSMakeRect(120, 0, 34, 32)];
        redact.accessibilityIdentifier = @"com.readdle.toolbar.main.redact";
        [w.contentView addSubview:ai];
        [w.contentView addSubview:tr];
        [w.contentView addSubview:share];
        [w.contentView addSubview:redact];

        const char *dylib = argc > 1 ? argv[1] : "build/ToolbarPatch.dylib";
        if (!dlopen(dylib, RTLD_NOW)) {
            fprintf(stderr, "FAIL: dlopen(%s): %s\n", dylib, dlerror());
            return 2;
        }

        [ai viewDidMoveToWindow];
        [tr viewDidMoveToWindow];
        [share viewDidMoveToWindow];
        [redact viewDidMoveToWindow];
        ai.hidden = NO;      // simulate re-show, then re-fire
        [ai viewDidMoveToWindow];

        CHECK(ai.hidden == YES, "AI entry hidden");
        CHECK(tr.hidden == YES, "Translate entry hidden");
        CHECK(share.hidden == NO, "share button untouched");
        CHECK(redact.hidden == NO, "redact button untouched");

        printf("ALL TESTS PASSED\n");
        return 0;
    }
}
