# Changelog

## v1.4.0 (2026-10-10)

- 新增 `--build NAME` / `--update NAME`；单模块只构建/替换对应 dylib 和元数据，
  不重签主程序、不修改其他模块。更新前持久保存旧模块，提交失败同时回滚库和元数据。
- 构建使用临时输出，VERSION 为单一版本来源；每个模块记录源码/构建配方/二进制哈希。
  安装前检查 provenance，防止旧元数据、构建漂移或暂存期间文件改变被错误标记为新版本。
- `--check` 显示版本、安装 hash、构建/源码/配方匹配情况；旧安装明确 unknown/untracked。
  新增 `--status-json` 身份报告和 `--record-compatibility` 只读观察采集。
- KeychainFix 保留 v1.3.2 的统一路由；仅改可选诊断为操作/结果码/错误说明/字段形状，
  不输出 service/account/group/data 值。新增诊断隐私回归检查。
- 建立用户确认的 v1.3.2 登录基线，人工验收与自动测试分开；采集不自动宣称通过。
- 整理 AGENTS、README、文档索引、架构、兼容证据、大版本适配手册与下一位 LLM 交接模板；
  保留并标注历史设计和逆向证据，明确不得重复 v1.3.1 的登录过滤回归。
- 新增单模块不改其他产物、元数据回滚、构建竞态、哈希漂移、CLI 参数及文档链接测试；
  临时 app 使用真实外部工具演练单模块更新。不自动部署真实 app/已正常的登录补丁。

## v1.3.2 (2026-10-10)

- 修复 v1.3.1 引入的账号持久化回归：撤回 service/class/DP/access-group 同时匹配
  的过滤条件，恢复 v1.3 对所有 SecItem 查询统一剥除 DP 路由键和访问组的行为。
- 保留已修复的构建、停用开关与空原函数保护。
- 回归测试覆盖缺少访问组、service、不同 DP 属性等查询，以及写入/读取查询属性
  不一致时仍路由到同一钥匙串。替身测试不等同于真实账号登录/重启验收。
- v1.3.1 的过滤方案已被用户真实使用证实不兼容；不再宣称该策略可替代原方案。

## v1.3.1 (2026-10-10)

- 修复 KeychainFix 构建：显式包含并链接 vendored fishhook，四 dylib universal 编译/签名/校验。
- 修复 SidebarPatch 原方法漏调用；覆盖双补丁双向加载、继承和独立禁用。
- KeychainFix 停用开关生效；仅匹配带非空 service 的 generic-password、DP=true、
  精确 PDF Expert 访问组查询，其他查询原样透传；原函数未解析时安全返回错误。
- Mach-O 注入器严格检查 thin/fat/fat64 边界、命令、section 和零填充；所有架构
  先内存校验，再原子写入；原位置更新旧补丁路径、保留依赖编号；拒绝重复命令和旧 first 插入模式。
- 安装在副本注入/签名/校验后提交，串行锁防止并发部署；进程内失败回滚 app/dylib。
- 新增完整官方备份（版本/构建号/哈希/签名），恢复拒绝错版本和旧单文件备份；
  `--backup-original` 可保存已有完整原版。取消自动清理备份和自动去隔离。
- 新增 `--build`/`--test`，严格 CLI 参数；状态检查校验所有架构及签名。
- 新增 25 项 Python 测试、调用链与钥匙串替身测试、真实 codesign 临时 app 部署演练。
- 同步 README/交接文档；fishhook 与官方 main 逐文件一致，许可证标注改为 BSD 3-Clause。
- 未部署真实应用；真实 UI/账号持久化仍需验收。本机现有 Widgets 扩展签名不通过，
  新安装器会拒绝在此状态继续部署，应先从官方来源恢复完整应用。

## v1.3 (2026-10-10)

- **新增 KeychainFix.dylib**：修复补丁版每次启动要求重新登录的问题。
  根因：ad-hoc 重签后 securityd 不认可 Data Protection Keychain 的 TeamID
  前缀访问组。解法：fishhook 重绑定 SecItem*，剥掉
  `kSecUseDataProtectionKeychain`/`kSecAttrAccessGroup`，把 keychain 读写
  重定向到传统登录钥匙串。
- 安装目录迁移：`~/Library/Application Support/PDFExpertPatcher` →
  `~/Library/PEPatch`（4 条 LC 的 header 空间预算）。
- 项目整理：AIPatch 移除；三个 UI 补丁 + KeychainFix 基础设施；
  fishhook vendored（BSD 3-Clause；v1.3 原标注已更正）。

## v1.2 (2026-10-10)

- **SidebarPatch**：编辑工具右侧栏 X 关闭按钮全部隐藏——全局 RDAKButton
  钩子（identifier `com.readdle.right-panel.close`），与容器类解耦。
- **ToolbarPatch**：工具栏 AI（`ai`）/翻译（`A文`）入口按钮隐藏
  （其面板为 SwiftUI 绘制，X 无法在 AppKit 层隐藏）。
- patch.sh 多 dylib 管线 + `--check`；handoff.md 适配手册；AIPatch 废弃。

## v1.0 (2026-10-09)

- **TabPatch**：顶部标签关闭按钮移到左侧（Safari 风格）。
- 注入管线：inject_lc.py（LC_LOAD_DYLIB，fat/thin、幂等）+ patch.sh
  （备份/注入/entitlements 过滤/ad-hoc 重签/去隔离/--restore）。
