# AI / Translate 菜单入口 — 2026-10-15

目标：/Applications/PDF Expert.app，官网 DMG 3.13.4 build 1177。
本轮 Hopper MCP list_documents 返回 Transport closed；使用 Xcode 的 nm、
llvm-objdump 对实际主程序 x86_64 slice 取证，没有修改 app。
地址仅适用于该版本的 x86_64；运行时补丁不使用地址或二进制偏移。

- PDFDocumentsTabContentMenuHelper 的 aiChatSummarizeAction: / aiChatExplainAction:
  实现入口分别为 0x10038a0b0 / 0x10038a0d0。
- 0x10038b9f5 附近构建本地化 Summarize；0x10038ba3a 读取
  aiChatSummarizeAction:，0x10038ba8c 调用 initWithTitle:target:action:。
- 0x10038bbf1 附近构建 Explain；0x10038bc41 读取 aiChatExplainAction:。
- 0x100389910 构建 Translate to（本地化键 com.readdle.context-menu.ai-chat.translate-to）；
  0x100389af6 以 aiChatTranslateAction: 生成语言项，0x100389b52 setSubmenu:。
  语言项类为 _TtC14PDF_Expert_DMG27AIChatTranslateTextMenuItem。
  父项是普通 NSMenuItem，因此通过直属语言子项识别，不能只藏子项。
- Base.lproj/MainMenu.nib 的 NIBArchive 字节中，Translate PDF、
  Kga-fc-IbL.title 与 toggleTranslationFeatureMainMenuAction: 相邻；
  en.lproj/MainMenu.strings 对应同一 object ID。Controller 在
  0x1005dfe98 / 0x1005e0ce5 的菜单校验分支检查这个 action。
- 0x1005c091f–0x1005c092d 读取 summarize: / explain: / translate:，
  对应 PDFDocumentsTabContentViewController 的文档 responder action。

过滤在 NSMenu.update 原实现之后和 NSMenuDidBeginTrackingNotification 执行。
主菜单及其后代豁免；普通同名标题不匹配。仅设置 hidden，保留 item、action、target。
这隐藏右键入口，不禁用 AI / 翻译业务；主菜单等其他入口仍可使用。

自动测试覆盖替身 AppKit 菜单，不代表真实 PDF 右键已人工验收。

## v1.4.1 残留根因与 v1.4.2 修复

用户于 2026-10-15 提供截图：其他三个入口已隐藏，Translate PDF 仍可见。
上一版从 MainMenu.nib 推断右键 action 是错误的；此前测试只验证了这个假设。

沿 PDFDocumentViewController pdfDocumentView:willPresentMenu:context:
→ 0x100615aa0 → 0x1006f7180 → PDFDocumentsTabContentMenuHelper 的
0x10038b7b0 菜单构建流程追踪：0x10038bf37／0x10038bf41 拼出 Swift
短字符串 Translate PDF，以 mainBundle 的 Localizable.strings 本地化；
0x10038bf98 调用 RDAppKit 的 NSMenuItem.init(title:actionClosure:)。
该导入也可由 nm 的 _$sSo10NSMenuItemC8RDAppKitE5title13actionClosure... 交叉确认。

实际 RDAppKit x86_64 工厂 0x49140：0x4918f 设置 `_closureAction:`；
0x49298–0x492a5 将 target 设成 item 自身。ActionClosureWrapper 存于关联对象，
不是 item.target。因此不能按 wrapper target 类匹配，也不能按主菜单 action 匹配。
修复精确匹配 `_closureAction:`、target==item、同一本地化键的标题三者。
新增真实形状的回归测试已在 1.4.1 dylib 上失败；保留同名普通项和其他闭包项。
