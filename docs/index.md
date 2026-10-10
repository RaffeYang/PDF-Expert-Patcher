# 文档索引

## 当前维护入口

| 文档 | 用途 |
|---|---|
| [../README.md](../README.md) | 日常使用、命令、更新、备份与恢复 |
| [../AGENTS.md](../AGENTS.md) | LLM 必须先读的工作基线与约束 |
| [handoff.md](handoff.md) | 大版本失效时的诊断、发现、修复与交接步骤 |
| [architecture.md](architecture.md) | 代码职责、运行时机制、构建和部署设计 |
| [compatibility.md](compatibility.md) | 人工验收与自动测试的证据边界、记录方法 |
| [compatibility.json](compatibility.json) | 已有兼容性证据及精确二进制哈希 |
| [../CHANGELOG.md](../CHANGELOG.md) | 发布变更和登录回归纠正 |
| [../src/vendor/README.md](../src/vendor/README.md) | fishhook 来源、许可证和哈希 |

## 历史与逆向资料

| 资料 | 定位 |
|---|---|
| [design.md](design.md) | v1.0 设计快照，不能作为当前安装步骤 |
| [dev-notes.md](dev-notes.md) | 排障历史；包含已废弃路线，先看现行手册 |
| [../analysis/FINDINGS.md](../analysis/FINDINGS.md) | 3.13.4 x86_64 标签布局证据 |
| [../analysis/ai-sidebar-findings.md](../analysis/ai-sidebar-findings.md) | AppKit/SwiftUI 侧栏与工具栏证据 |
| [../analysis/hopper_dump.txt](../analysis/hopper_dump.txt) | 对应旧版的反编译导出，地址不能直接迁移 |
| `superpowers/specs/`、`superpowers/plans/` | 各轮设计与执行记录；不是现行行为的唯一来源 |

遇到冲突：代码决定实际行为；VERSION 决定项目版本；compatibility.json 决定已确认
的运行证据；README/handoff 描述现行操作。历史记录用于解释原因，不用来覆盖当前实现。
