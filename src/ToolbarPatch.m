// src/ToolbarPatch.m — Patch 3: remove the AI / Translate entries from the
// main toolbar and document context menus (their side panels are SwiftUI-drawn and cannot have their
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
static IMP g_origMenuUpdate;
static id g_menuTrackingObserver;

static void TBLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"[ToolbarPatch] %@", [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

static BOOL TBDebug(void) { return getenv("TOOLBARPATCH_DEBUG") != NULL; }
static BOOL TBDisabled(void) { return getenv("TOOLBARPATCH_DISABLE") != NULL; }

// Evidence: analysis/ai-context-menu-findings.md (3.13.4 DMG).
// A nil target uses the document responder chain. Do not match generic action
// names on unrelated explicit targets, or localized display titles.
static BOOL TBIsContextEntry(NSMenuItem *item) {
    NSString *action = item.action ? NSStringFromSelector(item.action) : @"";
    // The document context entry uses RDAppKit's closure initializer, not the
    // main-menu action. Its target is the item itself, action _closureAction:.
    // Resolve the same Localizable.strings key used by the app; never hide
    // arbitrary same-title items or all closure-backed menu items.
    if ([action isEqualToString:@"_closureAction:"] && item.target == item) {
        NSString *title = [[NSBundle mainBundle] localizedStringForKey:@"Translate PDF"
                                                               value:@"Translate PDF" table:nil];
        if ([item.title isEqualToString:title]) return YES;
    }
    if ([action isEqualToString:@"aiChatSummarizeAction:"] ||
        [action isEqualToString:@"aiChatExplainAction:"] ||
        [action isEqualToString:@"aiChatTranslateAction:"] ||
        [action isEqualToString:@"toggleTranslationFeatureMainMenuAction:"]) return YES;
    if ([action isEqualToString:@"summarize:"] ||
        [action isEqualToString:@"explain:"] ||
        [action isEqualToString:@"translate:"]) {
        Class document = objc_getClass("_TtC14PDF_Expert_DMG36PDFDocumentsTabContentViewController");
        if (!item.target || (document && [item.target isKindOfClass:document])) return YES;
    }
    Class translation = objc_getClass("_TtC14PDF_Expert_DMG27AIChatTranslateTextMenuItem");
    if (translation && [item isKindOfClass:translation]) return YES;
    // Translate to has no useful action itself: identify the language submenu.
    for (NSMenuItem *child in item.submenu.itemArray) {
        if (child.action == NSSelectorFromString(@"aiChatTranslateAction:") ||
            (translation && [child isKindOfClass:translation])) return YES;
    }
    return NO;
}

static void TBFilterContextMenu(NSMenu *menu) {
    if (TBDisabled() || ![menu isKindOfClass:[NSMenu class]]) return;
    NSMenu *root = menu;
    while (root.supermenu) root = root.supermenu;
    if (root == NSApp.mainMenu) return;
    for (NSMenuItem *item in menu.itemArray) {
        if (TBIsContextEntry(item)) {
            if (!item.hidden) {
                item.hidden = YES;
                if (TBDebug()) TBLog(@"hid context entry: action=%@ class=%@",
                                    item.action ? NSStringFromSelector(item.action) : @"-",
                                    NSStringFromClass(item.class));
            }
        } else if (item.submenu) {
            TBFilterContextMenu(item.submenu);
        }
    }
}

static void TBMenuUpdate(id self, SEL cmd) {
    if (g_origMenuUpdate) ((void (*)(id, SEL))g_origMenuUpdate)(self, cmd);
    TBFilterContextMenu(self);
}

static void TBInstallMenuFilter(void) {
    Method method = class_getInstanceMethod([NSMenu class], @selector(update));
    if (method) g_origMenuUpdate = method_setImplementation(method, (IMP)TBMenuUpdate);
    g_menuTrackingObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { TBFilterContextMenu(note.object); }];
    TBLog(@"context menu filter installed%s", TBDisabled() ? " (disabled)" : "");
}

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
    TBInstallMenuFilter();
    g_origImpsBySelector = [NSMutableDictionary new];
    Class cls = objc_getClass("RDAKButton");
    if (!cls) {
        TBLog(@"RDAKButton not found — toolbar button hook inactive (version change?)");
        return;
    }
    TBHookClass(cls, @selector(viewDidMoveToWindow), (IMP)TBToolbarButtonMovedToWindow);
    TBLog(@"global RDAKButton hook installed%s", TBDebug() ? " (debug on)" : "");
}

__attribute__((constructor)) static void ToolbarPatchMain(void) {
    @autoreleasepool { TBInstall(); }
}
