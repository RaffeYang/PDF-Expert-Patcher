# PDF Expert Patcher — LLM 接手入口

先读 [README.md](README.md)、[docs/handoff.md](docs/handoff.md)、
[docs/compatibility.md](docs/compatibility.md)。当前项目版本只从 `VERSION` 读取。
当前机制在 [docs/architecture.md](docs/architecture.md)；文档目录在 [docs/index.md](docs/index.md)。

## 必须保留的工作基线

- 四个模块保持独立：TabPatch / SidebarPatch / ToolbarPatch / KeychainFix。
- 用户已确认 PDF Expert 3.13.4 build 1177 + KeychainFix v1.3.2 恢复登录持久化。
  精确二进制哈希和确认范围见 docs/compatibility.json；不要把它推广为所有功能/所有架构通过。
- v1.3.1 把 KeychainFix 限制为 service/class/DP/group 同时匹配，导致每次启动重新登录。
  已撤回。保持所有 SecItem 查询统一移除 DP 路由键/访问组，读写一致。
  未获得真实查询证据与登录/退出/重启验收，不得再次以“优化”为由收窄。
- 不读取/输出/删除用户钥匙串数据。诊断只记录操作、错误码和字段是否存在。
- 单模块修改使用 `--build NAME` / `--update NAME`，不要顺手替换其他已正常模块。
- Mach-O 路径迁移必须保留 dylib ordinal。不要删除再追加旧 dependency 或恢复 first 插入。
- 保留原方法调用链；Sidebar/Toolbar hook 同一个 selector，双向加载和禁用测试都要通过。

## 工作方式

1. `git status --short`，保留已有未提交修改；检查 VERSION 和当前安装状态。
2. 明确实际失败模块、PDF Expert 版本/构建号/渠道/架构/症状，先复现再修改。
3. 修改前补失败测试；原始逆向地址只适用于记录中的版本/架构，不盲用。
4. 构建/测试默认只操作项目和临时测试 app。部署真实应用需在用户授权范围内；
   已授权时不重复询问。不得强杀 PDF Expert，尊重未保存文档提示。
5. `./patch.sh --test` 通过后，只报告已验证的范围。真实 UI/账号验收要单独记录。
6. 更新 VERSION、CHANGELOG、当前文档和兼容记录；保留历史证据，不用历史计划覆盖现行实现。
7. 用户未要求时，不提交/推送 Git，不创建远程仓库，不写外部记忆目录。

## 常见陷阱

- 当前安装器需要工具生成的 `.json` 构建元数据。手工编译的旧 dylib 不要伪造版本。
- `--check` 是只读检查；签名/加载命令正常不证明功能正常。
- 完整官方备份与单 dylib 更新备份不同。旧 `PDF Expert.orig.*` 不是完整官方恢复来源。
- 不使用 `codesign --deep --sign` 重写嵌套身份；deep verification 与 deep signing 不同。
- `build/`、`backup/` 是本地产物，可能含 root 所有文件；先查权限，不盲用 sudo 重跑全部流程。
- 本地 `opencode.json` 不代表任意 LLM 自动有 Hopper MCP；先探测当前环境可用工具。
