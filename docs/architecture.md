# 当前架构

项目版本见 [../VERSION](../VERSION)。适配的已知 app 基线是官网 DMG 版
PDF Expert 3.13.4 build 1177；App Store 版与未来版本需重新识别模块名和签名约束。

## 模块边界

| 模块 | 机制与匹配物 | 修改入口 | 回归测试 |
|---|---|---|---|
| TabPatch | `TabContentView.layout`；重写关闭按钮约束并加幂等 identifier | `src/TabPatch.m` | `tests/TestHost.m` |
| SidebarPatch | `RDAKButton.viewDidMoveToWindow`；identifier 含 `com.readdle.right-panel.close` | `src/SidebarPatch.m` | `tests/SidebarPatchTest.m`、`tests/HookChainTest.m` |
| ToolbarPatch | 同一 selector；精确匹配 `com.readdle.toolbar.main.chat` / `.translate` | `src/ToolbarPatch.m` | `tests/ToolbarPatchTest.m`、`tests/HookChainTest.m` |
| KeychainFix | fishhook 重绑定 SecItemAdd/CopyMatching/Update/Delete；统一 sanitize 查询 | `src/KeychainFix.m`、`src/vendor/` | `tests/KeychainFixTest.m` |

TabPatch 的已知类名 `_TtC14PDF_Expert_DMG14TabContentView` 以及 ivar
`closeButton`、`iconView`、`titleView`、`titleMaxWidthConstraint` 都是私有实现。
Sidebar/Toolbar 需调用保存的真实原 IMP，不能漏调用、把自身存为原方法或破坏链。
AI/翻译面板在旧版是 SwiftUI，隐藏工具栏入口不等于改变其内部视图。

KeychainFix 的跨 image 路由范围沿用用户已确认可用的 v1.3 策略。
`KFSanitize` 对所有查询统一去除 `kSecUseDataProtectionKeychain` 和
`kSecAttrAccessGroup`，保留其他字段；Update 的新值字典不修改。
读/写查询可能具有不同字段，不能以“必须同时存在某些字段”为条件拆分路由。
fishhook rc=0 仅表示注册成功，不保证未来 OS/image 都已重绑。

## 构建与版本追踪

`tools/env.sh` 定位 Xcode/CLT、SDK 和 Python；`tools/build.sh [NAME...]`
默认构建四模块，指定名字则只构建对应模块。所有名字先校验。

编译在 build 内临时目录完成，生成 universal dylib，签名/校验后生成 `NAME.json`。
然后替换输出文件。二进制和元数据并非单个原子对象；部署时必须再次检查哈希，
构建中断导致两者不匹配时拒绝安装，重新构建即可。

`tools/provenance.py` 记录：schema、patch、project_version、source_sha256、
recipe_sha256、binary_sha256、built_at。源码哈希只包含该模块及必要 vendor 文件；
配方哈希包含 build.sh、env.sh、provenance.py。它不构成完整 SDK/编译器可重现性证明。
安装元数据还记录 build_binary_sha256、installed_at、target_app；重签可能改变实际字节，
所以原构建哈希与实际安装哈希分别保存。`matches_build` 比较实际字节，不等于源码兼容。

旧库没有元数据时显示 unknown/untracked，仍可检查真实哈希和签名；不猜测版本。
源码匹配只是 provenance 证据，不证明真实 UI/账号通过。

`identity_report` 供 JSON 状态和兼容性采集共用：记录 app 实际路径、主程序哈希、
各 Mach-O slice 的架构和补丁依赖路径；模块身份与主程序是否静态引用预期路径分开。
报告拒绝非法 Mach-O，不把静态引用当作运行时加载成功。

## 全量安装

`patch.sh` 构建 → 只读 preflight → 正常退出 app → `tools/deploy.py install`：

1. 完整签名校验与 thin/fat/fat64、header 空间检查。
2. 锁内准备 app 副本和四个新模块；现有补丁命令原位置改路径，缺少的追加。
3. 原版且签名完整时保存官方完整快照；副本注入、过滤受限 entitlement、外层签名。
4. dylib 与元数据一起提交，再替换 app；任何进程内失败尝试回滚。

`migrated_bytes` 不能改变已有 dependency 的 ordinal；重复补丁命令直接拒绝迁移。
`inject_lc.py first` 已移除。不要重排 dyld bind/chained-import/nlist 对应的依赖编号。

## 单模块更新

`patch.sh --update NAME` 只构建 NAME；preflight-update 要求每个架构已在目标路径
恰好注入一次，且构建产物、元数据、架构、签名均通过校验。
锁内暂存新库/元数据，保存 `backup/updates/NAME/<时间>-<哈希>/` 中的旧库与恢复记录，
只替换该模块两个文件；不复制、注入、修改或重签 app，不改变其他模块。

因此单模块更新不把“已有完整 app 签名通过”当作改库的前提；已有嵌套签名问题不会
被它修复或掩盖。全量安装和 `--check` 仍报告完整签名问题。

## 回滚边界

app/多个 dylib/元数据不是单个原子事务。工具用临时文件、串行锁和进程内回滚降低风险，
不保证 SIGKILL/断电自动恢复。回滚本身失败时保留含 `RECOVERY_REQUIRED` 的 `.pepatch-*`。
完整 app 恢复只接受匹配版本/构建、主程序哈希与官方 Readdle 签名的完整快照。
模块更新备份只能恢复对应模块，不是官方 app 快照；旧无元数据备份不能冒充当前源码构建。

Python API 不自动退出 app；直接调用 deploy.py 的维护者需先确认目标进程已退出。
正常用户使用 patch.sh。自动测试直接调用 API，仅针对不会运行的临时替身 app。
