# v1.3.1 Implementation Plan

**Goal:** 实施已授权的构建、钩子、备份恢复、部署、注入器与文档修复。
**Architecture:** shell 保留 CLI；Python 负责受校验的二进制修改及部署事务；ObjC 保留四个 dylib。
**Tech Stack:** Bash 3.2、Python 3 标准库、Objective-C/AppKit、vendored fishhook。

## 任务与验收

- [x] 注入器：先增加 subprocess 合成 thin/fat、重复注入、损坏边界、非零 padding
  和失败不写入测试；运行确认缺陷，然后实现严格校验和原子写入。
- [x] 钩子：添加 headless AppKit 原方法计数及双向加载测试，确认当前失败；修复
  SidebarPatch 调用链。KeychainFix 使用替身 SecItem 函数测试路由及禁用，不碰真钥匙串。
- [x] 构建：添加 tools/build.sh 和 tools/test.sh；四 dylib universal 编译；
  执行真实构建，检查 lipo 架构；原有三个 UI 测试继续运行。
- [x] 部署：tools/deploy.py 实现预检、完整备份、签名副本、锁、替换和回滚；
  测试使用临时 app 和外部工具替身，覆盖签名失败、提交失败、版本不匹配。
  patch.sh 保留 --check/--restore，添加 --build/--test 和严格参数检查。
- [x] 文档：README/CHANGELOG/handoff/dev-notes 对齐当前实现；记载旧备份限制、
  查询匹配范围、恢复及更新路径和真实 UI/账号验收未覆盖的部分。
- [x] 终检：tools/test.sh、bash -n、Python 测试、git diff --check；记录结果。

## 最终验证（2026-10-10）

- `./patch.sh --test` 返回 0：四个 universal dylib 编译/签名验证通过；25 项 Python
  测试通过；3 个原有 UI 程序、8 组双补丁加载/禁用组合、钥匙串路由与禁用通过。
- 临时测试 app 使用真实 codesign/lipo/ditto 两次安装通过；旧路径在原 ordinal
  更新；没有完整官方快照时恢复按预期失败且保持 app 签名有效。
- 完整原版恢复由 Python 临时 fixture + 外部签名工具替身验证，未使用真实
  Readdle 原版快照演练。真实账号/UI 验收未执行。
- 独立只读审查指出并修复 ordinal 重排问题；复审未发现其他重要缺陷。
- `git diff --check` 通过；CLI --help 成功，未知参数返回 2。
- `./patch.sh --check` 对真实 app 按预期返回 1，指出既有 Widgets Dmg Extension
  x86_64 签名无效、缺少完整官方快照。真实 app 及已安装 dylib 未部署更新。
- 不自动提交 Git；完整测试输出为本地 gitignored 的 build/verification.log。

## v1.3.2 回归纠正

用户部署后反馈登录不能保持。v1.3.1 收窄条件的替身测试不足以证明实际兼容性。
已撤回严格路由，恢复 v1.3 全查询统一 sanitize；更新测试要求不同形状的读写一致。
`PEPATCH_BUILD_DIR="$PWD/build/login-repair" ./patch.sh --test` 全部通过。
已仅替换实际安装的 KeychainFix.dylib，验证签名和哈希，主程序哈希不变。
旧库保存在 build/login-repair/previous-KeychainFix-2292886e39b2d214.dylib。
真实账号重启持久化等待用户验收，不能凭测试输出认定已通过。
