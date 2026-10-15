#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while (0)
static int updates;
static NSMenuItem *reshown;
static void OriginalUpdate(id self, SEL cmd) { (void)self; (void)cmd; updates++; reshown.hidden = NO; }
static NSMenuItem *Item(NSString *title, NSString *action) {
    return [[NSMenuItem alloc] initWithTitle:title action:action ? NSSelectorFromString(action) : NULL keyEquivalent:@""];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK(argc == 2, "provide ToolbarPatch dylib");
        [NSApplication sharedApplication];
        Class trClass = objc_allocateClassPair([NSMenuItem class], "_TtC14PDF_Expert_DMG27AIChatTranslateTextMenuItem", 0);
        objc_registerClassPair(trClass);
        method_setImplementation(class_getInstanceMethod([NSMenu class], @selector(update)), (IMP)OriginalUpdate);
        CHECK(dlopen(argv[1], RTLD_NOW), dlerror());
        BOOL disabled = getenv("TOOLBARPATCH_DISABLE") != NULL;

        NSMenu *menu = [NSMenu new];
        NSMutableArray *wanted = [NSMutableArray new];
        for (NSString *action in @[@"aiChatSummarizeAction:", @"aiChatExplainAction:", @"toggleTranslationFeatureMainMenuAction:", @"summarize:", @"explain:", @"translate:"]) {
            NSMenuItem *item = Item(@"任意本地化标题", action);
            [menu addItem:item]; [wanted addObject:item];
        }
        NSMenuItem *parent = Item(@"任意语言", nil);
        parent.submenu = [NSMenu new];
        [parent.submenu addItem:Item(@"中文", @"aiChatTranslateAction:")];
        [menu addItem:parent]; [wanted addObject:parent];
        NSMenuItem *typedParent = Item(@"专用翻译类型", nil);
        typedParent.submenu = [NSMenu new];
        [typedParent.submenu addItem:[[trClass alloc] initWithTitle:@"日文" action:NULL keyEquivalent:@""]];
        [menu addItem:typedParent]; [wanted addObject:typedParent];
        NSMenuItem *sameTitle = Item(@"Summarize", @"copy:");
        [menu addItem:sameTitle];
        NSMenuItem *normal = Item(@"Copy", @"copy:"); [menu addItem:normal];
        NSMenuItem *alreadyHidden = Item(@"Other", @"paste:"); alreadyHidden.hidden = YES; [menu addItem:alreadyHidden];
        NSObject *foreignTarget = [NSObject new];
        NSMenuItem *foreign = Item(@"Translate PDF", @"translate:"); foreign.target = foreignTarget; [menu addItem:foreign];
        reshown = wanted[0];
        [menu update];
        CHECK(updates == 1, "original update called once");
        for (NSMenuItem *item in wanted) CHECK(item.hidden == !disabled, "requested context entry hidden independently of title");
        CHECK(!sameTitle.hidden && !normal.hidden && alreadyHidden.hidden, "unrelated entries unchanged");
        CHECK(!foreign.hidden, "generic action on unrelated explicit target preserved");
        CHECK(menu.numberOfItems == 12, "menu structure preserved");
        [menu update];
        CHECK(updates == 2 && reshown.hidden == !disabled, "repeated update filters after original re-show");

        NSMenuItem *late = Item(@"Late", @"aiChatExplainAction:"); [menu addItem:late];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:menu];
        CHECK(late.hidden == !disabled, "tracking filters late-created entries");

        NSMenuItem *group = Item(@"Other group", nil); group.submenu = [NSMenu new];
        NSMenuItem *nested = Item(@"Nested", @"aiChatSummarizeAction:");
        [group.submenu addItem:nested]; [group.submenu addItem:Item(@"Copy", @"copy:")]; [menu addItem:group];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:menu];
        CHECK(!group.hidden && nested.hidden == !disabled, "nested filtering preserves unrelated parent");

        NSMenu *main = [NSMenu new]; NSApp.mainMenu = main;
        NSMenuItem *top = Item(@"Tools", nil); top.submenu = [NSMenu new]; [main addItem:top];
        NSMenuItem *mainAction = Item(@"Translate PDF", @"toggleTranslationFeatureMainMenuAction:");
        [top.submenu addItem:mainAction];
        NSMenuItem *mainAI = Item(@"Summarize", @"aiChatSummarizeAction:"); [top.submenu addItem:mainAI];
        [top.submenu update];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:main];
        CHECK(!mainAction.hidden && !mainAI.hidden, "main-menu descendants preserved");
        NSMenu *closureMenu = [NSMenu new];
        NSString *translationTitle = [[NSBundle mainBundle] localizedStringForKey:@"Translate PDF" value:@"Translate PDF" table:nil];
        NSMenuItem *closure = Item(translationTitle, @"_closureAction:"); closure.target = closure;
        [closureMenu addItem:closure];
        NSMenuItem *otherClosure = Item(@"Copy", @"_closureAction:"); otherClosure.target = otherClosure;
        [closureMenu addItem:otherClosure];
        NSMenuItem *plainSameTitle = Item(translationTitle, @"copy:"); [closureMenu addItem:plainSameTitle];
        NSMenuItem *foreignClosure = Item(translationTitle, @"_closureAction:"); foreignClosure.target = foreignTarget;
        [closureMenu addItem:foreignClosure];
        [closureMenu update];
        CHECK(closure.hidden == !disabled, "real RDAppKit self-targeted Translate PDF closure hidden");
        CHECK(!otherClosure.hidden && !plainSameTitle.hidden && !foreignClosure.hidden, "other closures and same-title items preserved");
        [closureMenu removeItem:closure]; [top.submenu addItem:closure]; closure.hidden = NO;
        [top.submenu update];
        CHECK(!closure.hidden, "main-menu closure remains visible");
        puts("CONTEXT MENU TESTS PASSED");
    }
    return 0;
}
