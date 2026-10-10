// src/ToolbarPatch.m — Patch 3: remove the AI / Translate entries from the
// main toolbar (their side panels are SwiftUI-drawn and cannot have their
// close buttons hidden at the AppKit level — see analysis/ai-sidebar-findings.md).
//
// Mechanism: same global button-level hook as SidebarPatch, matching the
// toolbar entry identifiers instead (both are RDAKButtons).
//
// Debug (TOOLBARPATCH_DEBUG=1): logs every non-matching RDAKButton once.
// Kill switch: TOOLBARPATCH_DISABLE=1.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// ---- configurable zone ------------------------------------------------------
static NSArray *TBToolbarIdentifiersToHide(void) {
    static NSArray *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[ @"com.readdle.toolbar.main.chat",       // AI
                   @"com.readdle.toolbar.main.translate" ]; // A文
    });
    return names;
}
// -----------------------------------------------------------------------------

static NSMutableDictionary<NSString *, NSValue *> *g_origImpsBySelector;

static void TBLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"[ToolbarPatch] %@", [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

static BOOL TBDebug(void) { return getenv("TOOLBARPATCH_DEBUG") != NULL; }
static BOOL TBDisabled(void) { return getenv("TOOLBARPATCH_DISABLE") != NULL; }

static NSString *TBIdent(NSView *v) {
    NSString *a = [v respondsToSelector:@selector(accessibilityIdentifier)]
                      ? [(id)v accessibilityIdentifier] : nil;
    if (a.length) return a;
    return v.identifier;
}

static IMP TBOrigForSelector(Class cls, SEL sel) {
    NSString *selName = NSStringFromSelector(sel);
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        NSString *key = [NSStringFromClass(c) stringByAppendingString:selName];
        NSValue *v = g_origImpsBySelector[key];
        if (v) return (IMP)v.pointerValue;
    }
    return NULL;
}

static void TBStoreOrig(Class cls, SEL sel, IMP orig) {
    NSString *key = [NSStringFromClass(cls) stringByAppendingString:NSStringFromSelector(sel)];
    g_origImpsBySelector[key] = [NSValue valueWithPointer:orig];
}

static void TBToolbarButtonMovedToWindow(id self, SEL _cmd);

static void TBHookClass(Class cls, SEL sel, IMP newImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    if (orig == (IMP)TBToolbarButtonMovedToWindow) {
        class_addMethod(cls, sel, newImp, method_getTypeEncoding(m));
        return;
    }
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
        Method own = class_getInstanceMethod(cls, sel);
        orig = method_getImplementation(own);
        method_setImplementation(own, newImp);
    }
    TBStoreOrig(cls, sel, orig);
}

static void TBToolbarButtonMovedToWindow(id self, SEL _cmd) {
    IMP orig = TBOrigForSelector([self class], _cmd);
    if (orig) ((void (*)(id, SEL))orig)(self, _cmd);
    NSView *b = self;
    if (TBDisabled()) return;
    NSString *ident = TBIdent(b);
    if (!ident.length) return;
    for (NSString *wanted in TBToolbarIdentifiersToHide()) {
        if ([ident isEqualToString:wanted]) {
            if (!b.isHidden) {
                b.hidden = YES;
                TBLog(@"hid toolbar entry: %@ in %@", ident,
                      b.superview ? NSStringFromClass([b.superview class]) : @"-");
            }
            return;
        }
    }
    if (TBDebug()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            TBLog(@"[btn] %@ frame=%@ ident=%@ in %@",
                  NSStringFromClass([b class]), NSStringFromRect(b.frame), ident,
                  b.superview ? NSStringFromClass([b.superview class]) : @"-");
        });
    }
}

static void TBInstall(void) {
    g_origImpsBySelector = [NSMutableDictionary new];
    Class cls = objc_getClass("RDAKButton");
    if (!cls) {
        TBLog(@"RDAKButton not found — patch inactive (version change?)");
        return;
    }
    TBHookClass(cls, @selector(viewDidMoveToWindow), (IMP)TBToolbarButtonMovedToWindow);
    TBLog(@"global RDAKButton hook installed%s", TBDebug() ? " (debug on)" : "");
}

__attribute__((constructor)) static void ToolbarPatchMain(void) {
    @autoreleasepool { TBInstall(); }
}
