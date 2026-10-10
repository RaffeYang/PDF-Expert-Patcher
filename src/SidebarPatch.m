// src/SidebarPatch.m — Patch 2: hide the close buttons of ALL right-side panels.
//
// Evidence (analysis/ai-sidebar-findings.md): every right-panel close button is
// an RDAKButton whose accessibilityIdentifier contains
// "com.readdle.right-panel.close", regardless of which tool presented the panel
// or which container class hosts it. So the most robust mechanism is a global,
// button-level hook: every RDAKButton entering a window self-inspects and hides
// itself on an identifier match. No container classes, no position heuristics.
//
// Debug (SIDEBARPATCH_DEBUG=1): logs every non-matching RDAKButton once, so a
// new/renamed close button reveals its identity for easy matching.
// Kill switch: SIDEBARPATCH_DISABLE=1.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// ---- configurable zone ------------------------------------------------------
static NSString * const kCloseIdentifier = @"com.readdle.right-panel.close";
// -----------------------------------------------------------------------------

static NSMutableDictionary<NSString *, NSValue *> *g_origImpsBySelector;

static void SBLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"[SidebarPatch] %@", [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

static BOOL SBDebug(void) { return getenv("SIDEBARPATCH_DEBUG") != NULL; }
static BOOL SBDisabled(void) { return getenv("SIDEBARPATCH_DISABLE") != NULL; }

static NSString *SBIdent(NSView *v) {
    NSString *a = [v respondsToSelector:@selector(accessibilityIdentifier)]
                      ? [(id)v accessibilityIdentifier] : nil;
    if (a.length) return a;
    return v.identifier;  // NSView.identifier and accessibilityIdentifier are
                          // separate stores in the wild — match either.
}

// Never store one of our own IMPs as "orig": dispatch would recurse forever.
// If a superclass is already hooked, walk the chain to its stored true original.
static IMP SBOrigForSelector(Class cls, SEL sel) {
    NSString *selName = NSStringFromSelector(sel);
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        NSString *key = [NSStringFromClass(c) stringByAppendingString:selName];
        NSValue *v = g_origImpsBySelector[key];
        if (v) return (IMP)v.pointerValue;
    }
    return NULL;
}

static void SBStoreOrig(Class cls, SEL sel, IMP orig) {
    NSString *key = [NSStringFromClass(cls) stringByAppendingString:NSStringFromSelector(sel)];
    g_origImpsBySelector[key] = [NSValue valueWithPointer:orig];
}

static void SBRDAKButtonMovedToWindow(id self, SEL _cmd);

static void SBHookClass(Class cls, SEL sel, IMP newImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    if (orig == (IMP)SBRDAKButtonMovedToWindow) {
        // Superclass already hooked: re-add newImp here, store nothing — the
        // superclass entry holds the TRUE original for the chain walk.
        class_addMethod(cls, sel, newImp, method_getTypeEncoding(m));
        return;
    }
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
        Method own = class_getInstanceMethod(cls, sel);
        orig = method_getImplementation(own);
        method_setImplementation(own, newImp);
    }
    SBStoreOrig(cls, sel, orig);
}

static void SBRDAKButtonMovedToWindow(id self, SEL _cmd) {
    IMP orig = SBOrigForSelector([self class], _cmd);
    if (orig) ((void (*)(id, SEL))orig)(self, _cmd);
    NSView *b = self;
    if (SBDisabled()) return;
    NSString *ident = SBIdent(b);
    if (ident.length && [ident containsString:kCloseIdentifier]) {
        if (!b.isHidden) {
            b.hidden = YES;
            SBLog(@"hid close button: frame=%@ ident=%@ in %@",
                  NSStringFromRect(b.frame), ident,
                  b.superview ? NSStringFromClass([b.superview class]) : @"-");
        }
        return;
    }
    if (SBDebug()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SBLog(@"[btn] %@ frame=%@ ident=%@ in %@",
                  NSStringFromClass([b class]), NSStringFromRect(b.frame), ident ?: @"-",
                  b.superview ? NSStringFromClass([b.superview class]) : @"-");
        });
    }
}

static void SBInstall(void) {
    g_origImpsBySelector = [NSMutableDictionary new];
    Class cls = objc_getClass("RDAKButton");
    if (!cls) {
        SBLog(@"RDAKButton not found — patch inactive (version change?)");
        return;
    }
    SBHookClass(cls, @selector(viewDidMoveToWindow), (IMP)SBRDAKButtonMovedToWindow);
    SBLog(@"global RDAKButton hook installed%s", SBDebug() ? " (debug on)" : "");
}

__attribute__((constructor)) static void SidebarPatchMain(void) {
    @autoreleasepool { SBInstall(); }
}
