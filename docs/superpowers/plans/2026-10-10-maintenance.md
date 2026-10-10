# v1.4.0 Maintenance Implementation Plan

**Goal:** 实施用户批准的四项维护优化并建立无需会话历史的 LLM 交接入口。
**Architecture:** 复用现有 staged deployment，单模块使用相同锁/回滚但不替换 app；独立标准库 provenance 与 compatibility 工具。
**Tech Stack:** Bash 3.2、Python 标准库、Objective-C/AppKit、fishhook。

- [x] 为 provenance 增加版本/源码/二进制漂移测试，先运行失败；实现构建与安装 sidecar、JSON 状态。
- [x] 为单模块更新增加不修改主程序/其他 dylib、未注入拒绝、签名失败/元数据失败回滚测试；实现 CLI 与部署。
- [x] 为诊断增加无敏感值断言，先失败；只改日志不改 KFSanitize，运行钥匙串路由/停用测试。
- [x] 兼容性采集不自动通过验收；记录用户确认的 v1.3.2 登录恢复基线；为默认 pending 测试。
- [x] 整理 README、AGENTS、handoff、architecture、compatibility 及历史文档入口；保持逆向证据。
- [x] 全部测试、真实临时 app 的单模块更新/重复全量安装、文档链接/CLI、独立代码审查；记录结果。

## 完成验证（2026-10-10）

- `PEPATCH_BUILD_DIR="$PWD/build/maintenance" ./patch.sh --test`：44 项 Python 测试、
  原生模块/双向 hook 链/Keychain 路由与禁用/诊断隐私检查全部通过。
- 临时 universal app：重复全量安装、单模块构建/更新、未选模块和主程序文件及 mtime
  不变、持久备份、拒绝无官方快照恢复均通过。测试日志：`build/maintenance/verification.log`。
- 独立审查提出的主程序身份缺失已修复并复查通过；采集绑定实际 app 路径、主程序
  SHA256、每个架构的补丁 LC 路径，不把库存在或静态引用当作人工通过。
- `./patch.sh --build` 已生成默认 build 内四个 v1.4.0 universal 库及 sidecar。
  `--record-compatibility`、`--status-json` 在实际 app 只读采集成功，人工结果保持 pending。
- 实际安装未修改；已确认正常的 KeychainFix SHA256 仍为
  `b619f24a4c277c711bcd8da4b4dc9d470c2dbb508ef423078b12ac3fb30b2a85`。
- 实际 `--check` 按预期报告现有 Widgets Dmg Extension.appex 的 x86_64 签名错误，
  且没有匹配的完整官方恢复快照。这不是自动测试失败，当前维护未修改该 app；
  全量安装会拒绝该状态，需用官方完整安装包恢复后再运行补丁。
- 文档链接、CLI 参数及 shell 语法检查通过；真实 v1.4.0 UI/账号重启与 arm64 运行未验收。
