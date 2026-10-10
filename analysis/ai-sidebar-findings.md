# FINDINGS — AI/Translate 侧栏与工具栏按钮（运行期取证 2026-10-10）

## 两种右侧栏

### Type-1：编辑工具面板（已隐藏 ✅）
- 容器：`_TtC14PDF_Expert_DMG15TitledPanelView`（240 宽一代）+
  `_TtC14PDF_Expert_DMG20TranslationPanelView`（注意 20 不是 19！）
- X 按钮：`RDAKButton`，`accessibilityIdentifier = com.readdle.right-panel.close`
- 隐藏方式：identifier 匹配（容器级 sweep + RDAKButton 全局自检双保险）

### Type-2：AI / Translate 面板（X 无法 AppKit 级隐藏 ❌ → 改为隐藏入口按钮 ✅）
- Copilot 容器：`_TtC14PDF_Expert_DMGP33_...16FeaturePanelView` → `AIChatUI.ChatView`
  - 头部：`AIChatUI.ChatHeaderView`（340×44）内是
    `NSHostingView<ChatHeaderSwiftUIView>`——**X 由 SwiftUI 直接绘制**，
    AppKit 层只有 `RDSwiftUIKit HoverView`（悬停效果包装，x=272 是"..."、x=304 是 X）
  - 藏 HoverView 宿主 = 只去掉悬停高亮，X 图标仍在（SwiftUI 画在自己的 layer）
- Translate 容器：`_TtC14PDF_Expert_DMG20TranslationPanelView` →
  `NSHostingView<AnyView>`，X 同样是 SwiftUI 绘制（x=304 HoverView）
- **最终方案（用户拍板）**：隐藏工具栏入口按钮——
  `com.readdle.toolbar.main.chat`（AI）、`com.readdle.toolbar.main.translate`（A文）
  两者都是 `RDAKButton`（宿主 `PDF_Expert_DMG.FeatureToolbarItemView`），全局钩子直接隐藏 ✅

## 其他容器情报

| 类 | 角色 |
|---|---|
| `PanelViewsFlowDockView` ident=com.readdle.left-panel | 左侧栏 dock（缩略图/摘要） |
| `GenericPropertiesInspectorView` | 注解工具属性内容区（X 不在其中，在容器头部） |
| `FloatingToolbarPanelView` | 底部浮动工具条（Measure/Scan 等，勿动） |
| `DocumentSummaryPanelView` | 左侧摘要面板 |
| `_TtC14PDF_Expert_DMGP33_...16FeaturePanelView` | AI 面板容器（私有子类命名） |

## 踩坑记录

1. **混淆名长度**：`TranslationPanelView` 是 20 字符（`_TtC14PDF_Expert_DMG20...`），
   猜 19 会 "not found"。
2. **RDAKButton 是纯 ObjC 类**：运行时名就是 `RDAKButton`，
   不是 `_TtC8RDAppKit10RDAKButton`。
3. **递归栈溢出（两次崩溃）**：父子类都被 hook 时，子类安装拿到的
   `method_getImplementation` 可能是父类上"我们自己的 IMP"，若当作 orig 存下
   → 调用自己无限递归。修复：`SBHookClass` 检测 orig 为任一自定义 IMP 时
   只加重定向、不存储，让 `SBOrigForSelector` 沿继承链找到真 orig。
4. **NSView.identifier ≠ accessibilityIdentifier**：两个独立存储，
   Readdle 用后者；匹配时两者都查。
5. **位置启发式兜底不可靠**：短容器（28pt 行）里 maxY 检查恒真，
   会误伤行内右侧小按钮——已移除，只信 identifier。
6. **SwiftUI 面板的 X 是延迟创建**：容器 move-to-window 时还不存在，
   需要 +0.3/+1/+3s 延时重扫。
