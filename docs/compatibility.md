# 兼容性证据与验收

[compatibility.json](compatibility.json) 记录已有人工证据，不能只改 app 版本号就沿用验收。
每条记录必须绑定 app 版本/构建、渠道、运行架构、模块哈希和明确的确认范围。

当前基线：用户确认 KeychainFix v1.3.2 恢复后账号登录正常，app 为官网 DMG
3.13.4 build 1177，Intel。其他功能未逐项确认，标为 not_recorded；arm64 只构建过，
不能标为真实运行通过。v1.4.0 新诊断代码未部署，不继承这次人工验收。

2026-10-10 只读检查仍发现当前安装的 `Widgets Dmg Extension.appex` 在 x86_64
上签名无效，且没有匹配的完整官方快照。补丁依赖路径均存在，但不能据此说整个
app 检查通过。未来全量安装前需从官方完整安装包恢复；本轮未修改该安装。

2026-10-15 只读检查显示安装四模块均为 v1.4.0，构建／源码身份匹配；这是静态观察，
不为其补记账号人工验收。v1.4.1 四个右键入口过滤须独立验收，自动 AppKit 替身
测试不证明真实 PDF 菜单效果，也不继承旧登录确认。

## 自动观察与人工结果分开

```bash
./patch.sh --check
./patch.sh --status-json
./patch.sh --record-compatibility
```

最后一条只生成 `build/compatibility-observation.json`，不会改 app、安装元数据或钥匙串。
所有 manual_validation 默认为 pending；automated_tests 默认为 not_run_by_capture。
`--status-json` 只报告身份/哈希，不替代 `--check` 的签名与架构检查。

观察记录同时绑定 app 的实际路径、主程序 SHA256、每个架构的补丁加载路径，
并用 `referenced_at_expected_path` 标明主程序是否静态引用预期安装路径。
目录中存在 dylib 不代表主程序引用了它；静态引用也不代表运行时已成功加载或功能通过。
历史人工确认未采集主程序哈希，不能追溯补写为当时已验证的证据。

确认需要验收的真实 app 后，先采集观察，再手动完成下面项目；若期间 app 或 dylib
更新，重新采集，不能把旧观察绑定到新二进制。

| 项目 | 人工操作与通过条件 |
|---|---|
| tab | 打开多个 PDF，切换标签；关闭按钮在左侧且可用 |
| sidebar | 打开实际编辑工具侧栏；目标关闭按钮隐藏，其他操作正常 |
| toolbar | AI/翻译入口隐藏；分享等其他入口正常 |
| context_menu | PDF 选中文字后右键，Summarize／Explain／Translate to 隐藏；页面右键的 Translate PDF 隐藏；复制等普通项和主菜单保持正常；重复打开菜单 |
| login_restart | 必要时登录一次，正常退出、重新启动，至少重复两轮仍登录 |
| save_pdf | 修改测试文档并保存、重新打开；不用唯一原始文件做实验 |
| extensions | 如果日常使用扩展，单独测试；不用则标 not_tested 并说明 |

由用户明确确认或维护者亲自完成后，才把对应字段从 pending 改为 pass/fail/not_tested，
在 manual_evidence 记录具体操作、轮数和确认来源；不要记录账号、token 或文档内容。
将确认后的记录追加到 docs/compatibility.json 的 records；保留以前失败和通过的证据。
测试日志可记录命令、返回码、时间和覆盖范围，不用“全部正常”代替细分结果。

## 已发生的回归

v1.3.1 严格过滤 Keychain 查询的替身测试通过，但用户实际部署后每次重启需登录。
v1.3.2 撤回过滤，统一路由后用户确认恢复。教训：模拟查询只证明写下的规则，不能
证明真实 app 使用这些字段。未来改变登录路径必须收集查询形状及真实重启证据。

诊断变量 `KEYCHAINFIX_DEBUG=1` 仅输出操作、结果码、系统错误说明、class 和字段存在性。
不输出 service/account/access-group 值或数据内容。若需要更深入证据，先在临时测试
钥匙串或受控替身中复现，不直接 dump 用户登录钥匙串。

2026-10-15 已仅部署 ToolbarPatch v1.4.1，主程序／加载路径及其他三个已装模块哈希
与部署前一致。静态观察追加到 compatibility.json 的 observations，所有人工项目仍
pending；PDF Expert 已重新打开，实际菜单效果尚未人工确认。旧模块备份：
`backup/updates/ToolbarPatch/1792071552560129000-16e6cd891a0d42cc/`。

用户随后确认 v1.4.1 的 Summarize／Explain／Translate to 已隐藏，截图证实
Translate PDF 仍可见；已追加部分验收失败记录。v1.4.2 修正该闭包入口的匹配，
实际右键效果等待再次人工确认，不沿用 v1.4.1 的四项整体验收。

v1.4.2 已仅部署 ToolbarPatch 并重新打开应用；主程序／依赖路径及其他三个模块
哈希与部署前一致。旧 1.4.1 模块备份：
`backup/updates/ToolbarPatch/1792072038991462000-4592a39fbb997e7d/`。

2026-10-15 用户安装 v1.4.2 后确认“测试了完美”，已追加四个右键项隐藏通过的
哈希绑定人工记录。仅确认 context_menu；顶部入口／常用侧栏为既有功能描述，
本轮未逐项重测，登录／保存／扩展也未扩大确认范围。更新步骤见
[更新操作指南](update-guide.md)。
