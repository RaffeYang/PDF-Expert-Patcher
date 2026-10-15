# AI context menu implementation plan

**Goal:** Hide the four requested context-menu entries in ToolbarPatch.

**Architecture:** Preserve the button hook. Add an NSMenu update wrapper and a
tracking notification observer; filter by selectors and translation item class.
Exclude the application main menu and its descendants. Never remove items.

**Constraints:** Keep all four modules independent, preserve original IMP calls,
do not change Keychain routing, do not commit/push, deploy only ToolbarPatch.

- [x] Record 3.13.4 x86_64 selector and nib evidence in analysis/ai-context-menu-findings.md.
- [x] Add tests/ContextMenuPatchTest.m: load existing dylib; assert context entries
  hidden after update, original update once, translation parent hidden, unrelated
  items and main menu unchanged, notification handles late additions; test disable.
- [x] Compile and run this test against 1.4.0; require failure on missing filtering.
- [x] Extend src/ToolbarPatch.m with action/type matching and recursive filtering;
  hook NSMenu.update independently of RDAKButton availability; retain observer.
- [x] Add native test and disabled run to tools/test.sh; rerun focused tests.
- [x] Set VERSION to 1.4.1; update README, CHANGELOG, architecture, handoff and
  compatibility documentation with explicit pending real UI acceptance.
- [x] Run ./patch.sh --build ToolbarPatch and ./patch.sh --test.
- [x] Run ./patch.sh --update ToolbarPatch with filesystem approval, then read
  identity and compatibility observation; verify other installed hashes unchanged.
