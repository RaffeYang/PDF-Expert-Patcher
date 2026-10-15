# 大版本适配与 LLM 交接手册

先读 [../AGENTS.md](../AGENTS.md)，当前版本见 [../VERSION](../VERSION)。
本手册给没有历史会话的维护者使用；当前实现见 [architecture.md](architecture.md)，
人工证据见 [compatibility.md](compatibility.md)。旧逆向证据只适用于其明确记录的版本/架构。

## 1. 接手后先做什么

1. 查看 `git status --short`、VERSION、CHANGELOG，保留现有修改。
2. 收集实际 app 的版本、构建号、渠道、架构和具体失败功能，区分安装失败与运行时失效。
3. 运行下列只读命令；即使 --check 非零，也要保留完整错误，不直接重签或覆盖。

```bash
./patch.sh --record-compatibility
./patch.sh --check
./patch.sh --status-json > build/identity.json
```

先保证 build 目录存在；`--record-compatibility` 会自动创建它。
观察报告的人工字段始终 pending，不允许自动标 pass。

4. 对照 docs/compatibility.json 的精确二进制哈希；unknown/untracked 表示旧元数据缺失，
   不说明模块不能用。不要为了补版本信息替换正常登录的 KeychainFix。
5. 先在临时/副本上验证，仅修改失败模块。用户明确要求部署时再使用正常 CLI 更新。

## 2. 症状分流

| 症状 | 先看证据 | 修改范围 |
|---|---|---|
| 无法启动/签名错误 | --check 的完整 codesign 错误，分清主程序/嵌套扩展/dylib | tools/deploy.py 的签名与安装；不先改 UI hook |
| 更新后四模块都没加载 | 每个架构的 LC_LOAD_DYLIB 和实际绝对路径 | 通常重新全量安装；先确认官方原版有效 |
| Tab class NOT FOUND | 类名、模块名、安装渠道 | TabPatch 常量与新的逆向证据 |
| 类存在但标签没移动 | closeButton/约束/ivar 类型、实际 layout 日志 | TabPatch FixConstraints 与 TestHost |
| 编辑侧栏 X 重现 | RDAKButton 是否存在、identifier 是否改变 | SidebarPatch 标识匹配 |
| AI/翻译入口重现 | 实际按钮类、identifier、AppKit/SwiftUI 归属 | ToolbarPatch；不按位置猜按钮 |
| AI/翻译右键项重现 | NSMenu.update／tracking 通知、action、语言子菜单类型；确认是否属于豁免的主菜单 | ToolbarPatch；不按本地化标题猜测 |
| 每次启动要求登录 | 已装 KeychainFix 哈希、停用变量、四个 SecItem 操作结果和字段形状 | 先对照已确认 v1.3.2 基线，不能再次收窄查询 |
| 仅 open 失败而直接 exec 正常 | LaunchServices、重复 Bundle ID、隔离和签名状态 | 启动路径问题，不能据此改 hook |

类字符串存在只表示静态证据，不保证 dylib 已加载或 UI 正常；fishhook rc=0 不表示
所有 image 的函数槽都已重绑。签名通过也不能证明账号或界面兼容。

## 3. 运行期诊断

先保存文档、正常退出所有真实 PDF Expert 进程；诊断会真正启动目标应用。
只在用户授权范围内进行，不强杀，不 dump 登录钥匙串。

```bash
TABPATCH_DEBUG=1 "/Applications/PDF Expert.app/Contents/MacOS/PDF Expert"
SIDEBARPATCH_DEBUG=1 TOOLBARPATCH_DEBUG=1 "/Applications/PDF Expert.app/Contents/MacOS/PDF Expert"
KEYCHAINFIX_DEBUG=1 "/Applications/PDF Expert.app/Contents/MacOS/PDF Expert"
```

每次只选所需诊断，退出当前实例后再换下一条。`open -a` 不可靠传递这些变量。
钥匙串日志仅输出操作、状态码、系统错误说明、class 和字段是否存在，不包含实际
service/account/access-group/data 值。收集读写是否具有不同形状，保留返回码。

TabPatch：

- 无 installed 日志：先查 dylib 加载，而不是重写约束。
- 有 installed，无 moved：可能 ivar/父视图或 trailing pin 不匹配，检查实际对象类型。
- 有 moved，视觉不对：检查 LEFT/LEADING、正反方向、等式/不等式、宽度预算和重复 layout。
- 不断 moved：检查 app 是否重建了约束或清除了幂等 identifier。

Sidebar/Toolbar：检查真实 identifier，不用“右上角小按钮”等位置启发式。
两个模块 hook 相同 selector，任何修改都要保留原方法调用链和双向加载测试。

KeychainFix：v1.3.1 的严格筛选已导致真实回归，v1.3.2 撤回后用户确认正常。
先核对正在加载的哈希与环境开关，保持 KFSanitize 对读写统一。
不根据替身测试推断真实查询包含某些字段；不要更改路由来消除单个错误码。

## 4. 新版本从零发现

先保留新版本完整官方快照和旧工作模块备份，不覆盖旧 analysis 证据。
使用当前架构；以下 x86_64 示例不能直接代表 arm64：

```bash
mkdir -p build
lipo "/Applications/PDF Expert.app/Contents/MacOS/PDF Expert" -thin x86_64 -output build/pe-x86_64.bin
strings -a build/pe-x86_64.bin | grep -E '_TtC.*Tab' | sort -u
nm build/pe-x86_64.bin | grep -F 'TabContentView'
strings -a build/pe-x86_64.bin | grep -E 'closeButton|rightPadding|buttonSize' | sort -u
strings -a build/pe-x86_64.bin | grep -E 'com\.readdle\.(right-panel|toolbar\.main)' | sort -u
```

旧类名 `_TtC14PDF_Expert_DMG14TabContentView` 中 DMG 是渠道线索；换 App Store 版
可能完全不同。从新版本的初始化、layout、点击方法交叉确认，不只改字符串碰运气。
已 strip 的符号或转成 SwiftUI 的 UI，需结合运行期和反编译，nm 无结果不代表功能不存在。

有 Hopper 时先探测本机是否已安装、文档是否已打开、MCP/CLI 是否在当前会话可用。
`opencode.json` 只是旧环境配置，不保证其他 LLM 自动拥有相同工具。

CLI 路线：更新 `tools/hopper_dump.py` 的 LABELS，使用新版本发现的名字/地址。
脚本默认写 analysis/hopper_dump.txt 并退出 Hopper；**先为新版本选择单独 OUT，保留旧导出**。

```bash
/usr/local/bin/hopper -e build/pe-x86_64.bin -Y "$(pwd)/tools/hopper_dump.py"
```

`-Y` 必须绝对路径。旧脚本所用 API：getAddressForName、getSegment(0)、
getProcedureAtAddress、decompile。不要假设 getAddressForLabel/getDisassembly 存在。
新版本 helper 地址必须重新发现；`sub_1001008c0` 等只属于 3.13.4 x86_64。
逆向证据见 [../analysis/FINDINGS.md](../analysis/FINDINGS.md)、
[../analysis/ai-sidebar-findings.md](../analysis/ai-sidebar-findings.md)。

## 5. 修改、验证、部署

| 要改的内容 | 源码与测试 |
|---|---|
| 标签类名/ivar/约束 | src/TabPatch.m；tests/TestHost.m；tools/hopper_dump.py |
| 侧栏标识 | src/SidebarPatch.m；tests/SidebarPatchTest.m；tests/HookChainTest.m |
| 工具栏标识 | src/ToolbarPatch.m；tests/ToolbarPatchTest.m；tests/HookChainTest.m |
| AI/翻译右键入口 | src/ToolbarPatch.m；tests/ContextMenuPatchTest.m；analysis/ai-context-menu-findings.md |
| 登录兼容性 | src/KeychainFix.m；tests/KeychainFixTest.m；真实退出/重启验收 |
| 二进制命令/路径 | tools/inject_lc.py；tests/test_inject_lc.py |
| 部署与回滚 | tools/deploy.py；tests/test_deploy.py；tests/real_deployment.sh |
| 版本/源码身份 | tools/provenance.py；tests/test_provenance.py；VERSION |
| 兼容证据采集 | tools/compatibility.py；tests/test_compatibility.py；docs/compatibility.json |

先让新增测试在旧实现失败，再修复，最后执行：

```bash
./patch.sh --build SidebarPatch   # 示例：只构建失败模块
./patch.sh --test                 # 完整回归；不修改真实 app
./patch.sh --update SidebarPatch  # 已获部署授权且已注入时，只替换此模块
./patch.sh --check
./patch.sh --record-compatibility
```

全量安装用于官方覆盖更新后的重新注入。单模块更新要求预期路径在每个架构恰好注入一次，
只改选定库及元数据，不重签主程序，不处理或隐藏已有 app 签名错误。
发布前更新 VERSION 和 CHANGELOG；源码变更后重新构建元数据，不用手改 hash 凑通过。
最后按 compatibility.md 验收真实功能，并记录受影响模块的具体结果。

## 6. 失败恢复

进程内失败会尝试回滚；回滚失败看错误指出的 `.pepatch-*` 和 RECOVERY_REQUIRED。
先检查 previous.app / previous-libraries 的内容与签名，不把不明文件覆盖到正在运行的 app。
断电/SIGKILL 不能保证自动回滚，保留恢复目录和错误信息再处理。

完整官方恢复：`./patch.sh --restore`，必须匹配版本/构建号/哈希/官方签名。
旧单主程序备份、模块更新备份不能当作完整 app；没有完整快照时通过官方来源恢复。

单模块更新的旧库在 `backup/updates/NAME/<时间>-<哈希>/`。若该备份具有有效 NAME.json，
维护者在确认 app 已正常退出后可用部署器直接恢复，而不重新构建覆盖备份：

```bash
# 用当前环境的 python3；先将路径换成已核验的备份目录。此命令会修改实际安装模块。
python3 tools/deploy.py update --patch SidebarPatch \
  --app "/Applications/PDF Expert.app" \
  --build "/path/to/verified/module-backup" \
  --backup "$PWD/backup" --install-dir "$HOME/Library/PEPatch"
```

这仍会保留回退前的模块备份。旧无元数据备份需要根据 recovery.json 核验实际 hash
后单独制定恢复操作，不得伪造项目版本或假称与当前源码一致。

## 7. 给下一位 LLM 的交接模板

```text
先读 AGENTS.md、README.md、docs/handoff.md、docs/architecture.md、docs/compatibility.md。
读取 VERSION、CHANGELOG、git status，保留已有修改。不要改变已确认工作的 KeychainFix 路由。
目标 app：<实际版本/构建/渠道/架构>；失败模块/症状：<实际描述>。
现有证据：<--check 输出、identity/compatibility 观察、只含非敏感内容的日志>。
先复现并补失败测试，只修复受影响模块。自动测试和人工验收分别记录。
不要假设旧 helper 地址或 Hopper MCP 仍可用，不要对正常模块顺手重签或覆盖。
最终提供：改变的文件、验证命令/结果、尚未验收部分、回滚备份位置和更新后的兼容记录。
```
