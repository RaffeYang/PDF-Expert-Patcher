# PDF Expert 更新后的补丁操作

当前补丁版本只从 [../VERSION](../VERSION) 读取。已适配与用户确认的右键菜单基线：
官网 DMG PDF Expert 3.13.4 build 1177、Intel。其他版本或 arm64 需重新验收。

## 当前功能

| 模块 | 实际范围 |
|---|---|
| TabPatch | 将文档标签的关闭按钮移到左侧 |
| SidebarPatch | 隐藏带 `com.readdle.right-panel.close` 标识的常用编辑工具右侧栏 X |
| ToolbarPatch | 隐藏顶部 AI／Translate 入口及右键 Summarize、Explain、Translate to、Translate PDF |
| KeychainFix | 保留已确认的统一钥匙串路由，处理补丁重签后的登录持久化 |

AI／Translate 的 SwiftUI 面板内部 X 没有修改。右键／工具栏过滤只隐藏这些入口，
没有禁用业务能力，主菜单仍保留。这不是自动监听更新的后台程序，官方更新后需手动运行。

## 官方更新覆盖安装后

1. 保存文档，完成官方更新。如果更新后的 app 签名不完整，使用官方 DMG 完整覆盖安装。
   保留本项目和 `~/Library/PEPatch/`，不要从旧版复制主程序或嵌套扩展到新版。
2. 在项目目录先检查并测试：

   ```bash
   cd /Users/RaffeYang/Coding/GitHub/PDF-Expert-Patcher
   ./patch.sh --check
   ./patch.sh --test
   ```

   官方更新后 `--check` 因缺少补丁加载命令而非零是预期可能情况；分别查看签名、
   架构和注入状态。完整 app 签名必须有效，才能继续全量安装。
   `--test` 只测试项目与临时 app，不证明新版 PDF Expert 内部实现仍兼容。
3. 完整签名正常且测试通过后全量重新安装：

   ```bash
   ./patch.sh
   ./patch.sh --check
   ./patch.sh --record-compatibility
   ```

   默认命令构建四模块，准备 app 副本、保存匹配的新版本完整官方快照、注入并签名验证，
   再提交替换。会正常请求退出 PDF Expert，尊重未保存提示；完成后手动重新打开应用。
   不使用 `--update` 恢复被官方更新抹掉的注入。
4. 实际验收：标签关闭位置、常用侧栏 X、顶部 AI／Translate、四个右键项、复制等普通项、
   测试 PDF 保存与重开、登录后正常退出并重启。登录至少重复两轮；按实际结果记录。

## 重新安装后只有部分功能失效

先保存 `--check` 输出和 `build/compatibility-observation.json`，记录新版本／build／渠道／
架构／具体症状，按 [handoff.md](handoff.md) 重新定位。类名、identifier、selector、
闭包结构和 SwiftUI 视图都可能被官方改变，重跑安装器不会自动发现并适配这些变化。

只修复失败模块，补上能复现实际形状的失败测试，完整回归通过后仅更新该模块，例如：

```bash
./patch.sh --build ToolbarPatch
./patch.sh --test
./patch.sh --update ToolbarPatch
./patch.sh --check
./patch.sh --record-compatibility
```

`--update` 要求该模块已在每个架构按预期路径注入一次，只替换指定 dylib 与元数据，
不重签主程序、不更新其他模块。不要为了修 UI 改动 KeychainFix 的查询路由。
逆向适配可使用 Hopper；当前会话能否连接 MCP 需现场检查。

## 权限、签名与回退

- 不要用 `sudo ./patch.sh` 重跑整个流程；权限失败时先查看报错目标和父目录所有权。
  本轮曾遇到 root 所有的 `.deploy.lock`，仅修复锁文件所有权后即可继续。
- 2026-10-15 当前安装的 Widgets Dmg Extension.appex x86_64 签名仍无效。
  单模块更新不修复此问题；在当前 app 上直接全量安装会被 preflight 拒绝。
  下一次完整官方覆盖安装后应重新核验该签名，不把这个历史问题当成新版必然问题。
- 单模块旧产物：`backup/updates/NAME/<时间>-<哈希>/`，含旧 dylib、元数据、恢复记录。
  回退操作见 [handoff.md](handoff.md)；不要手工伪造构建元数据。
- 完整回退：`./patch.sh --restore` 只接受匹配当前版本／build 的完整官方快照。
  缺少快照时使用对应官方安装包；旧单主程序备份不能恢复整个 bundle 签名。

详细的静态观察与人工验收边界见 [compatibility.md](compatibility.md)。
