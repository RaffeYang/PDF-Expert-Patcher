#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <dlfcn.h>
static int calls;
static void Original(id self, SEL cmd) { calls++; }
#define CHECK(c, m) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", m); return 1; } } while (0)
int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK(argc >= 2, "provide dylibs in load order");
        Class cls = objc_allocateClassPair([NSView class], "RDAKButton", 0);
        class_addMethod(cls, @selector(viewDidMoveToWindow), (IMP)Original, "v@:");
        objc_registerClassPair(cls);
        Class child = objc_allocateClassPair(cls, "TestRDAKChild", 0);
        objc_registerClassPair(child);
        for (int i = 1; i < argc; i++) CHECK(dlopen(argv[i], RTLD_NOW), dlerror());
        for (Class type in @[cls, child]) {
            for (NSString *ident in @[@"com.readdle.right-panel.close", @"com.readdle.toolbar.main.chat", @"com.readdle.toolbar.main.share"]) {
                NSView *view = [[type alloc] initWithFrame:NSZeroRect];
                view.accessibilityIdentifier = ident;
                int before = calls;
                [view viewDidMoveToWindow];
                CHECK(calls == before + 1, "original must be called exactly once");
                BOOL expected = ([ident containsString:@"right-panel.close"] && !getenv("SIDEBARPATCH_DISABLE")) ||
                                ([ident hasSuffix:@".chat"] && !getenv("TOOLBARPATCH_DISABLE"));
                CHECK(view.hidden == expected, "correct hide/disable behavior");
            }
        }
        puts("HOOK CHAIN TESTS PASSED");
    }
    return 0;
}
