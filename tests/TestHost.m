// tests/TestHost.m — 用 PDF Expert 的确切 ObjC 类名注册假 TabContentView，
// 复刻其约束布局，验证 TabPatch.dylib 的重写逻辑。退出码 0=全部通过。
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static NSString * const kID = @"TabPatch.closeLeading";

static NSLayoutConstraint *Find(NSArray *l, id a, NSLayoutAttribute aa, id b, NSLayoutAttribute bb) {
    for (NSLayoutConstraint *c in l) {
        if (![c isKindOfClass:[NSLayoutConstraint class]]) continue;
        BOOL forward  = (c.firstItem == a && c.firstAttribute == aa && c.secondItem == b && c.secondAttribute == bb);
        BOOL backward = (c.firstItem == b && c.firstAttribute == bb && c.secondItem == a && c.secondAttribute == aa);
        if (forward || backward) return c;
    }
    return nil;
}

#define CHECK(cond, msg) do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); exit(1); } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        // 1. Register a fake class under PDF Expert's exact ObjC name, with the same ivars.
        const char *name = "_TtC14PDF_Expert_DMG14TabContentView";
        Class cls = objc_allocateClassPair([NSView class], name, 0);
        class_addIvar(cls, "closeButton", sizeof(id), log2(sizeof(id)), @encode(id));
        class_addIvar(cls, "iconView", sizeof(id), log2(sizeof(id)), @encode(id));
        class_addIvar(cls, "titleView", sizeof(id), log2(sizeof(id)), @encode(id));
        class_addIvar(cls, "titleMaxWidthConstraint", sizeof(id), log2(sizeof(id)), @encode(id));
        objc_registerClassPair(cls);

        // 2. Instance + subviews.
        NSView *tab = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 300, 28)];
        NSButton *closeButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *iconView = [[NSView alloc] initWithFrame:NSZeroRect];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        NSTextField *titleView = [NSTextField labelWithString:@"Some long document title"];
        titleView.translatesAutoresizingMaskIntoConstraints = NO;
        [tab addSubview:iconView];
        [tab addSubview:titleView];
        [tab addSubview:closeButton];
        object_setIvar(tab, class_getInstanceVariable(cls, "closeButton"), closeButton);
        object_setIvar(tab, class_getInstanceVariable(cls, "iconView"), iconView);
        object_setIvar(tab, class_getInstanceVariable(cls, "titleView"), titleView);

        // 3. Replicate the app's REAL constraints (per Hopper/runtime dump):
        //    icon/title use LEFT attributes with paired equal/inequality pins,
        //    the close button is trailing-pinned via VFL with size 20.
        NSLayoutConstraint *iconLeft = [NSLayoutConstraint constraintWithItem:iconView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:tab attribute:NSLayoutAttributeLeft multiplier:1 constant:12];
        NSLayoutConstraint *iconCenterY = [NSLayoutConstraint constraintWithItem:iconView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:titleView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
        NSLayoutConstraint *titleGTE = [NSLayoutConstraint constraintWithItem:titleView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:tab attribute:NSLayoutAttributeLeft multiplier:1 constant:12];
        NSLayoutConstraint *titleEQ = [NSLayoutConstraint constraintWithItem:titleView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:tab attribute:NSLayoutAttributeLeft multiplier:1 constant:12];
        NSLayoutConstraint *titleWidthBudget = [NSLayoutConstraint constraintWithItem:titleView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationLessThanOrEqual toItem:tab attribute:NSLayoutAttributeWidth multiplier:1 constant:-48];
        NSLayoutConstraint *btnTrail = [NSLayoutConstraint constraintWithItem:tab attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:closeButton attribute:NSLayoutAttributeTrailing multiplier:1 constant:8];
        NSLayoutConstraint *btnWidth = [NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:20];
        NSLayoutConstraint *btnHeight = [NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:20];
        [NSLayoutConstraint activateConstraints:@[iconLeft, iconCenterY, titleGTE, titleEQ, titleWidthBudget, btnTrail, btnWidth, btnHeight]];
        // Real app keeps the titleMaxWidthConstraint ivar nil in this configuration:
        object_setIvar(tab, class_getInstanceVariable(cls, "titleMaxWidthConstraint"), nil);

        // 4. Load the patch.
        const char *dylib = argc > 1 ? argv[1] : "build/TabPatch.dylib";
        if (!dlopen(dylib, RTLD_NOW)) {
            fprintf(stderr, "FAIL: dlopen(%s): %s\n", dylib, dlerror());
            return 2;
        }
        CHECK(objc_getClass(name) == cls, "fake class is visible to dylib");

        // 5. Layout twice — second pass proves idempotency.
        [tab layoutSubtreeIfNeeded];
        [tab layoutSubtreeIfNeeded];

        // 6. Assertions (padding=8, buttonSize=20, shift=28 — mirrors real app).
        NSLayoutConstraint *btnLead = Find([tab constraints], closeButton, NSLayoutAttributeLeading, tab, NSLayoutAttributeLeading);
        CHECK(btnLead != nil, "closeButton leading pin exists");
        CHECK([btnLead.identifier isEqualToString:kID], "leading pin carries our identifier");
        CHECK(btnLead.constant == 8, "leading pin constant reuses old padding (8)");
        CHECK(btnTrail.active == NO, "original trailing pin deactivated");
        NSLayoutConstraint *iconLeftNow = Find([tab constraints], iconView, NSLayoutAttributeLeft, tab, NSLayoutAttributeLeft);
        CHECK(iconLeftNow != nil, "icon left pin still exists");
        CHECK(iconLeftNow.constant == 12 + 28, "icon shifted right by buttonSize+padding (40)");
        NSLayoutConstraint *titleGTENow = Find([tab constraints], titleView, NSLayoutAttributeLeft, tab, NSLayoutAttributeLeft);
        CHECK(titleGTENow != nil && titleGTENow.relation == NSLayoutRelationGreaterThanOrEqual, "title GTE pin exists");
        CHECK(titleGTENow.constant == 12 + 28, "title GTE pin shifted to 40");
        BOOL foundTitleEQ = NO;
        for (NSLayoutConstraint *c in [tab constraints]) {
            if ([c isKindOfClass:[NSLayoutConstraint class]] && c.firstItem == titleView &&
                c.firstAttribute == NSLayoutAttributeLeft && c.secondItem == tab &&
                c.relation == NSLayoutRelationEqual && c.constant == 40) foundTitleEQ = YES;
        }
        CHECK(foundTitleEQ, "title EQ pin (pri 750) shifted to 40");
        CHECK(titleWidthBudget.constant == -48, "width budget untouched (-48)");
        CHECK(btnWidth.constant == 20 && btnHeight.constant == 20, "button size untouched");

        printf("ALL TESTS PASSED\n");
        return 0;
    }
}
