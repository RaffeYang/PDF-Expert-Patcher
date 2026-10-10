# 开发笔记 — 排障记录与教训

> 历史排障记录。现行命令、策略与验收以 README、docs/handoff.md、docs/compatibility.md 为准。
> 本文含已失败/废弃路线，不按旧实验命令操作真实钥匙串或重签嵌套代码。


> 适配新版本的**权威操作指南在 `docs/handoff.md`**（本文 §4 仅存档，勿按此执行，
> 以免两份指南漂移）。本文记录排障过程与踩坑教训。

逆向与调试过程中踩过的坑，按时间线记录。后续适配新版本 PDF Expert 时先读这篇。

## 1. 逆向结论速查

（Tab 详见 `analysis/FINDINGS.md`；侧栏/工具栏详见 `analysis/ai-sidebar-findings.md`；原始导出在 `analysis/hopper_dump.txt`）

- 标签 UI 在**主可执行文件**（非框架），Swift 模块 `PDF_Expert_DMG`
- 核心类：`_TtC14PDF_Expert_DMG14TabContentView`（单标签视图）
  - ivar：`closeButton`(RDAKButton)、`iconView`(NSImageView)、`titleView`(TabTitleView)、
    `titleToIconConstraint`、`titleMaxWidthConstraint`（后者两个在此配置下为 nil）
  - `initWithFrame:` 是**未实现的**（reportUnimplementedInitializer + ud2）→
    所有标签经 NIB `initWithCoder:` 创建，公共初始化在 `sub_1001008c0`（巨型 VFL 状态机）
- 真实运行期约束（TABPATCH_DEBUG=1 dump，2026-10-09）：

```
TabTitleView.centerY == SELF.centerY - 1              (1000, EQ)
NSImageView.centerY == TabTitleView.centerY           (1000, EQ)
NSImageView.LEFT   == SELF.LEFT + 12                 (1000, EQ)
TabTitleView.LEFT  >= SELF.LEFT + 12                 (1000, GTE)
TabTitleView.LEFT  == SELF.LEFT + 12                 (750,  EQ)
TabTitleView.width <= SELF.width - 48                (249,  LTE)
RDAKButton.centerY == SELF.centerY                   (1000, EQ)
RDAKButton: VFL H:[closeButton(==20)]-8-| → trailing 钉右侧 + 宽高 20
```

- **关键坑**：app 混用 LEFT/RIGHT（手写约束）与 LEADING/TRAILING（VFL）两套属性。
  dylib 匹配必须两套都查，且标题的成对 GTE+EQ 约束要一起移位。
- 宽度预算 `-48` 在按钮移到左侧后依然正确（40 左偏移 + 8 右边距），无需改动。

## 2. 签名/注入排障记录（重要）

症状：注入 + ad-hoc 重签后，app 启动即被杀，崩溃报告
`termination: CODESIGNING "Taskgated Invalid Signature"`（死在 `_dyld_start`）。

按顺序定位到三个独立问题：

1. **app 外的 dylib 未签名**：`codesign --deep` 只管 app bundle 内部，够不到
   `~/Library/PEPatch/TabPatch.dylib`。
   → patch.sh 在拷贝 dylib 后必须 `codesign --force --sign -` 它。
2. **`--deep` 重签嵌套框架导致被杀**：把几十个 Readdle 框架全部改成 ad-hoc
   （并剥掉原 entitlements）后 taskgated 拒绝。
   → **不要用 `--deep`**，只重签外层（主程序）；嵌套代码保持原签名
   （未被修改、依然有效；无 hardened runtime 所以无库校验问题）。
3. **Team-ID 绑定的 entitlements + ad-hoc = 必死**：
   `com.apple.application-identifier`、`icloud-*`、`ubiquity-*`、
   `team-identifier`、`associated-domains` 在无 TeamID 的签名下不可能通过校验。
   → patch.sh 用 python 过滤这些 key，保留无害项
   （apple-events、audio-input、bookmarks.app-scope、scripting-targets）。

对照实验（留存于开发过程）：完全不动拷贝 ✓ 存活；注入+仅外层重签 ✓ 存活；
注入+`--deep` ✗ 被杀；+未过滤 entitlements ✗ 被杀。

其他备注：
- **shell 陷阱**：`set -o pipefail` 下用 `grep -q` 探测大输出（strings 25MB），
  grep 匹配即退出 → strings 收 SIGPIPE(141) → pipefail 判管道失败 → 检查恒为假。
  大输入探测要用 `grep ... >/dev/null`（消费完整输入）。patch.sh 的 tab class
  检查踩过此坑。
- `open` 启动 build/ 下同 Bundle ID 的**副本**会报
  `RBSRequestErrorDomain Code=5 Launch failed`——直接执行二进制可绕过；
  正式 app 在 /Applications 无此问题。
- Hopper CLI：`-Y` 脚本路径**必须绝对路径**（相对路径报
  `Cannot execute Python script`）；脚本结尾 `os._exit(0)` 让 Hopper 自动退出；
  Hopper Python API 无 `getAddressForLabel`（用 `getAddressForName`）、
  无 `doc.getSegmentContaining`（用 `doc.getSegment(0)`）、
  `Procedure` 没有 `getDisassembly`（用 `decompile()`）。
- `DYLD_INSERT_LIBRARIES` 对 hardened runtime 的 app 无效 → 才选择改主程序 + 重签路线。

## 3. dylib 设计要点（维护时注意）

- hook 点是 NSView 的 `layout`（TabContentView 未自带 override；若未来版本自带，
  `class_addMethod` 失败分支会改为 wrap 原有 override，两种情况都正确）
- 幂等锚点：给新建/改写的约束打 `identifier = "TabPatch.closeLeading"`；
  app 重建约束后 identifier 消失 → 下次 layout 自动重新应用（自愈）
- 静默降级：`objc_getClass` 找不到目标类只打 log，app 正常运行
- 调试：环境变量 `TABPATCH_DEBUG=1` 输出 subviews + 全量约束 dump
  （注意 `open -a` 不传环境变量，要直接 exec 二进制）

## 4. 适配新版本的步骤

**已迁移至 `docs/handoff.md`**（§1 诊断决策树 → §2 文件映射 → §3 验证闭环 →
§4 从零发现）。handoff 是唯一权威版本，本文不再维护适配步骤副本。

## 5. keychain 登录持久化排障记录（v1.3）

- 根因：登录 token 存 Data Protection Keychain，访问组 TeamID 前缀
  （`3L68KQB4HG.com.readdle.PDFExpert-Mac`），访问授权依赖 Apple 签发身份；
  ad-hoc 重签后 securityd 拒绝读写（-34018 类）。
- 实验：V1 只保留 application-identifier → app 活但 keychain 仍失败；
  V2 加 keychain-access-groups → AMFI 杀。**entitlement 路线是死路。**
- 解法：KeychainFix.dylib 用 fishhook 重绑定 SecItem*，剥掉
  `kSecUseDataProtectionKeychain`/`kSecAttrAccessGroup` → 读写落到登录钥匙串。
- 实现坑：`__interpose` 节方案被 dyld 拒（first 插入 + RTLD_NEXT 组合
  符号解析失败）；改用 fishhook（遍历间接符号表 + 重绑 GOT 槽）一次成功。
- v1.3 历史人工验证：当时确认登录钥匙串中有对应条目且重启仍登录。
  当前诊断不再建议导出整个钥匙串；使用字段形状/结果码及人工登录重启验收。


## 6. v1.3.1 稳定性修复与验证边界

- v1.3 的构建命令遗漏 fishhook include/source；v1.3.1 的 tools/build.sh 显式编译。
- SidebarPatch 的 g_origRDAKButtonMove 从未赋值，导致原方法未调用。已改为存储的
  原 IMP 查找；双补丁两种加载顺序均有原方法恰好一次断言。
- KeychainFix 旧停用函数未使用；现构造器检查开关。无非空 service 的宽泛查询
  不重定向，避免剥除访问组后扩大 Copy/Delete 查询范围；保留具体 service 原值。
- 上述 §5 的登录成功是 v1.3 历史证据，不代表收窄路由后的真实账号验收。
- 2026-10-10 只读检查当前 app：3.13.4 build 1177，外层 ad-hoc；deep/strict 校验
  报 Widgets Dmg Extension.appex 的 x86_64 签名无效。此次代码修改未部署到此 app。
- 不通过重签嵌套扩展掩盖签名问题；从官方安装包恢复完整 app 后再安装。
- 恢复主程序或删除 _CodeSignature 不等于恢复官方原版。tools/deploy.py 只接受
  完整官方快照；旧 PDF Expert.orig.* 保留但不用于自动恢复。
- 新部署取消自动去隔离；首次启动受 Gatekeeper 检查时应由用户核实来源后处理。
- `rebind_symbols` rc=0 只代表注册成功，不保证所有 image 均重绑。替身测试验证
  路由逻辑，实际账号登录/重启仍需单独验证。

- 独立审查纠正了一个迁移缺陷：删除旧 LC 再追加会重排 dylib ordinal，破坏
  dyld bind/chained imports。现改为原位置重写补丁命令，依赖顺序不变，缺少的才
  追加；重复依赖拒绝迁移。旧 `first` 参数也移除，避免同类重排风险。

## 7. v1.3.2 登录回归修复

用户反馈：v1.3 可以保持登录，部署 v1.3.1 后每次启动重新登录。
本次检查安装的 KeychainFix.dylib 时间为 16:23，与构建产物一致。
v1.3.1 的严格条件没有真实查询形状证据；新增“缺少访问组的读取与带访问组的
写入使用同一路由”测试可复现策略不兼容。撤回 KFShouldRedirect，恢复 v1.3
对所有查询统一 KFSanitize，保留有效停用和空原函数保护。

前面的替身测试验证了我写下的过滤规则，却没证明真实账号兼容，这是验证缺口。
真实登录/退出/重新启动仍需用户操作确认；不读取用户 token，不删除钥匙串条目。

## 8. v1.4.0 维护能力

增加单模块构建/部署、构建与安装 provenance、兼容性观察和 LLM 接手入口。
KeychainFix 只改 debug 格式（不含真实 service/account/group/data 值），不改 KFSanitize。
用户已确认的 v1.3.2 二进制继续保留在实际安装目录，新版本未自动部署。
当前人工基线绑定 docs/compatibility.json 中的 hash；不能因 VERSION 改变迁移验收结论。
详细现行操作转至 docs/handoff.md，机制转至 docs/architecture.md，本文不复制新命令。
