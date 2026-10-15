# AI / Translate 右键入口过滤

用户已于 2026-10-15 确认采用方法三。保持四模块独立，在 ToolbarPatch 中过滤
Summarize、Explain、Translate to、Translate PDF 的右键入口，保留主菜单。
不修改 SwiftUI 面板、KeychainFix 或其他模块，不提交或推送 Git。

匹配 action 和翻译子菜单专用类型，不匹配显示标题。NSMenu.update 调用原实现后
过滤；菜单开始 tracking 时再次过滤，覆盖预先构建和延迟填充的菜单。
Translate to 的父项通过直属子项的 aiChatTranslateAction: / 专用类型识别。
只设置 hidden，不移除对象或禁用业务函数；保留原菜单结构、target、action。
TOOLBARPATCH_DISABLE 同时停用工具栏和菜单过滤。

先验证旧实现失败，再验证普通项、标题同名项、主菜单、嵌套菜单、动态重建、
原 update 恰调用一次及停用开关。完整测试通过后仅更新 ToolbarPatch；
记录真实应用的部署哈希，实际右键效果等待人工确认。
