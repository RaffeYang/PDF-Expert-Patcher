// src/TabPatch.m — PDF Expert: move the tab close button from the right edge
// to the left edge of each tab (Safari style) by rewriting Auto Layout
// constraints at runtime. Degrades silently if the target class is missing.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static NSString * const kConstraintID = @"TabPatch.closeLeading";
static const char *kTabContentViewClassName = "_TtC14PDF_Expert_DMG14TabContentView";

static void (*g_originalLayout)(id, SEL);

static void TPLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"[TabPatch] %@", [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

static id IvarValue(id obj, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    return ivar ? object_getIvar(obj, ivar) : nil;
}

static NSLayoutConstraint *First(NSArray *list, BOOL (^pred)(NSLayoutConstraint *)) {
    for (NSLayoutConstraint *c in list)
        if ([c isKindOfClass:[NSLayoutConstraint class]] && pred(c)) return c;
    return nil;
}

// Orientation-agnostic match: pins item a's attribute aa to item b's attribute bb.
static BOOL IsPin(NSLayoutConstraint *c, id a, NSLayoutAttribute aa, id b, NSLayoutAttribute bb) {
    BOOL forward  = (c.firstItem == a && c.firstAttribute == aa && c.secondItem == b && c.secondAttribute == bb);
    BOOL backward = (c.firstItem == b && c.firstAttribute == bb && c.secondItem == a && c.secondAttribute == aa);
    return forward || backward;
}

static NSString *AttrName(NSLayoutAttribute a) {
    switch (a) {
        case NSLayoutAttributeLeading: return @"leading";
        case NSLayoutAttributeTrailing: return @"trailing";
        case NSLayoutAttributeLeft: return @"left";
        case NSLayoutAttributeRight: return @"right";
        case NSLayoutAttributeTop: return @"top";
        case NSLayoutAttributeBottom: return @"bottom";
        case NSLayoutAttributeWidth: return @"width";
        case NSLayoutAttributeHeight: return @"height";
        case NSLayoutAttributeCenterX: return @"centerX";
        case NSLayoutAttributeCenterY: return @"centerY";
        case NSLayoutAttributeFirstBaseline: return @"firstBaseline";
        case NSLayoutAttributeLastBaseline: return @"lastBaseline";
        default: return @"?";
    }
}

static NSString *ItemName(NSView *tabView, id item) {
    if (item == nil) return @"-";
    if ([item isEqual:tabView]) return @"SELF";
    NSString *cls = NSStringFromClass([item class]);
    // Shorten: drop common prefixes for readability
    cls = [cls lastPathComponent];
    return [NSString stringWithFormat:@"%@<%p>", cls, item];
}

static void DumpConstraints(NSView *tabView, NSView *closeButton) {
    if (!getenv("TABPATCH_DEBUG")) return;
    TPLog(@"---- subviews of %@<%p> ----", NSStringFromClass([tabView class]), tabView);
    for (NSView *v in tabView.subviews) {
        NSString *fid = [v respondsToSelector:@selector(accessibilityIdentifier)] ? [v accessibilityIdentifier] : @"";
        TPLog(@"%@ frame=%@ ident=%@", ItemName(tabView, v), NSStringFromRect(v.frame), fid);
    }
    TPLog(@"---- constraints of %@ ----", ItemName(tabView, tabView));
    for (NSLayoutConstraint *c in tabView.constraints) {
        if (![c isKindOfClass:[NSLayoutConstraint class]]) continue;
        TPLog(@"%@.%@ == %@.%@ x%g + %g  pri=%g  rel=%ld  id=%@  active=%@",
              ItemName(tabView, c.firstItem), AttrName(c.firstAttribute),
              ItemName(tabView, c.secondItem), AttrName(c.secondAttribute),
              c.multiplier, c.constant, c.priority, (long)c.relation,
              c.identifier ?: @"-", c.active ? @"Y" : @"N");
    }
    for (NSLayoutConstraint *c in closeButton.constraints) {
        if (![c isKindOfClass:[NSLayoutConstraint class]]) continue;
        TPLog(@"[close] %@ x%g + %g active=%@",
              AttrName(c.firstAttribute), c.multiplier, c.constant, c.active ? @"Y" : @"N");
    }
}

// Collect EVERY constraint pinning sub's left/leading edge to tabView's left/leading
// edge (either orientation, any relation) — the app mixes LEFT (code) and
// LEADING (VFL) attributes and uses paired equal/inequality constraints.
static NSMutableArray *LeftPins(NSView *tabView, NSView *sub) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSLayoutConstraint *c in tabView.constraints) {
        if (![c isKindOfClass:[NSLayoutConstraint class]]) continue;
        if (IsPin(c, sub, NSLayoutAttributeLeft, tabView, NSLayoutAttributeLeft) ||
            IsPin(c, sub, NSLayoutAttributeLeading, tabView, NSLayoutAttributeLeading)) {
            [result addObject:c];
        }
    }
    return result;
}

static void FixConstraints(NSView *tabView) {
    NSButton *closeButton = IvarValue(tabView, "closeButton");
    if (![closeButton isKindOfClass:[NSButton class]] || closeButton.superview != tabView) return;

    NSArray *held = tabView.constraints;
    for (NSLayoutConstraint *c in held)
        if ([c.identifier isEqualToString:kConstraintID]) return;  // already patched

    NSView *iconView = IvarValue(tabView, "iconView");
    NSTextField *titleView = IvarValue(tabView, "titleView");
    NSLayoutConstraint *titleMaxWidth = IvarValue(tabView, "titleMaxWidthConstraint");

    // 1) The pin that holds the button to the right edge. The VFL
    //    (`H:[closeButton(==buttonSize)]-rightPadding-|`) yields a trailing pin;
    //    hand-written variants may use right/right — check both.
    NSLayoutConstraint *trailingPin = First(held, ^BOOL(NSLayoutConstraint *c) {
        return IsPin(c, closeButton, NSLayoutAttributeTrailing, tabView, NSLayoutAttributeTrailing);
    });
    if (!trailingPin) trailingPin = First(held, ^BOOL(NSLayoutConstraint *c) {
        return IsPin(c, closeButton, NSLayoutAttributeRight, tabView, NSLayoutAttributeRight);
    });
    if (!trailingPin) {
        TPLog(@"trailing pin not found on %@ — skipping", tabView);
        return;
    }

    // 2) Button size from its width constraint (VFL: closeButton(==buttonSize)).
    NSLayoutConstraint *widthC = First(closeButton.constraints, ^BOOL(NSLayoutConstraint *c) {
        return c.firstItem == closeButton && c.secondItem == nil && c.firstAttribute == NSLayoutAttributeWidth;
    });
    if (!widthC) widthC = First(held, ^BOOL(NSLayoutConstraint *c) {
        return c.firstItem == closeButton && c.secondItem == nil && c.firstAttribute == NSLayoutAttributeWidth;
    });
    CGFloat buttonSize = widthC ? widthC.constant : closeButton.intrinsicContentSize.width;
    if (buttonSize <= 0) buttonSize = 14;

    CGFloat padding = fabs(trailingPin.constant);
    if (padding <= 0) padding = 8;
    CGFloat shift = buttonSize + padding;

    // 3) Move: deactivate the right-edge pin, install a leading pin.
    trailingPin.active = NO;
    NSLayoutConstraint *leadingPin =
        [NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeLeading
                                    relatedBy:NSLayoutRelationEqual toItem:tabView
                                    attribute:NSLayoutAttributeLeading multiplier:1.0 constant:padding];
    leadingPin.identifier = kConstraintID;
    leadingPin.active = YES;

    // 4) Shift every left/leading pin of icon & title to the right by `shift`.
    //    This preserves the app's own internal arrangement (icon/title spacing)
    //    and covers paired equal + inequality constraints.
    NSView *subs[2] = { iconView, titleView };
    for (size_t i = 0; i < 2; i++) {
        NSView *sub = subs[i];
        if (![sub isKindOfClass:[NSView class]] || sub.superview != tabView) continue;
        NSMutableArray *pins = LeftPins(tabView, sub);
        if (pins.count == 0) {
            if (sub == iconView) {
                // Fallback: chain the icon right after the relocated button.
                NSLayoutConstraint *lead =
                    [NSLayoutConstraint constraintWithItem:iconView attribute:NSLayoutAttributeLeading
                                                relatedBy:NSLayoutRelationEqual toItem:closeButton
                                                attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:padding];
                lead.identifier = kConstraintID;
                lead.active = YES;
                TPLog(@"icon had no left/leading pin; chained to closeButton.trailing");
            } else {
                TPLog(@"WARNING: title has no left/leading pin — it may overlap the button");
            }
            continue;
        }
        for (NSLayoutConstraint *c in pins) {
            c.constant += (c.firstItem == sub) ? shift : -shift;
        }
    }

    // 5) Shrink the optional max-width constraint (ivar may be nil in some tab
    //    configurations; the app's own `width <= superview.width - 48` style
    //    budget already stays correct once the title starts further right).
    if ([titleMaxWidth isKindOfClass:[NSLayoutConstraint class]] &&
        titleMaxWidth.active && titleMaxWidth.constant > shift + 40) {
        titleMaxWidth.constant -= shift;
    }

    [tabView setNeedsLayout:YES];
    DumpConstraints(tabView, closeButton);
    TPLog(@"close button moved to leading edge (padding=%.1f size=%.1f shift=%.1f)", padding, buttonSize, shift);
}

static void PatchedLayout(id self, SEL _cmd) {
    static BOOL inFlight = NO;
    if (!inFlight) {
        inFlight = YES;
        @try {
            @autoreleasepool { FixConstraints(self); }
        } @catch (NSException *e) {
            TPLog(@"fix failed: %@", e);
        }
        inFlight = NO;
    }
    if (g_originalLayout) g_originalLayout(self, _cmd);
}

static void Install(void) {
    Class cls = objc_getClass(kTabContentViewClassName);
    if (!cls) {
        TPLog(@"%s not found — version change? Running unpatched.", kTabContentViewClassName);
        return;
    }
    Method m = class_getInstanceMethod(cls, @selector(layout));
    if (!m) {
        TPLog(@"layout method unavailable — aborting.");
        return;
    }
    IMP orig = method_getImplementation(m);
    if (!class_addMethod(cls, @selector(layout), (IMP)PatchedLayout, method_getTypeEncoding(m))) {
        // The class already overrides layout itself — wrap that instead.
        Method own = class_getInstanceMethod(cls, @selector(layout));
        orig = method_getImplementation(own);
        method_setImplementation(own, (IMP)PatchedLayout);
    }
    g_originalLayout = (void (*)(id, SEL))orig;
    TPLog(@"installed on %s", class_getName(cls));
}

__attribute__((constructor)) static void TabPatchMain(void) {
    @autoreleasepool { Install(); }
}
