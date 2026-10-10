# PDF Expert Tab Close Button Patcher — 设计文档

> **历史快照（v1.0，仅 TabPatch 单补丁时期）**。当前四补丁架构、keychain 方案与
> 维护指南以 `docs/handoff.md`、`README.md` 为准；本文保留原始设计决策供追溯。

日期：2026-10-09
状态：已确认（用户批准）

## 目标

把 PDF Expert 3.x（macOS）顶部标签条的**关闭按钮从标签右侧移到左侧**（Safari 风格），
以独立 dylib + 可重跑 patcher 的形态交付。软件更新后只需再运行一次 `patch.sh`。

## 目标环境（已确认）

- macOS + Intel (x86_64)；PDF Expert 3.13.4，universal binary（x86_64 + arm64）
- App 位于 `/Applications/PDF Expert.app`，Bundle ID `com.readdle.PDFExpert-Mac`
- 签名带 **Hardened Runtime**（Readdle TeamID 3L68KQB4HG）→ `DYLD_INSERT_LIBRARIES` 不可用
- Hopper Disassembler 已安装（含 CLI `/usr/local/bin/hopper` + license）
- Xcode 已安装

## 逆向情报（静态分析已确认）

标签 UI 在主可执行文件内（Swift 模块 `PDF_Expert_DMG`）：

- `_TtC14PDF_Expert_DMG14TabContentView`：单个标签视图
  - ivar：`closeButton`、`titleView`、`iconView`、`titleToIconConstraint`、`titleMaxWidthConstraint`、`selected`、`linkMode` 等
  - 方法：`onCloseButtonClick:`、`initWithFrame:`、`initWithCoder:`、mouse 事件系列
- `_TtC14PDF_Expert_DMG7TabView`：标签条（`updateConstraints`、mouseDown/Drag 拖拽换位）
- 二进制内 VFL 字符串 `H:[closeButton(==buttonSize)]-rightPadding-|`：
  把 closeButton 钉在右侧的约束，即补丁目标

## 架构

```
PDF Expert Patcher/
├── src/TabPatch.m          # dylib 源码（ObjC，单文件）
├── tools/inject_lc.py      # Mach-O LC_LOAD_DYLIB 注入器（幂等）
├── patch.sh                # 一键补丁入口（更新后重跑）
├── analysis/               # Hopper 反编译导出（参考用）
└── backup/                 # 原始主程序备份（--restore 用）
```

### 1. 逆向阶段（Hopper）

- `hopper -e <x86_64 slice> -Y dump.py` 自动导出 `TabContentView` init 方法与
  `TabView updateConstraints` 的伪代码；定位 VFL 约束创建位置与图标/标题 leading 常量
- 导出结果存 `analysis/`，作为 swizzle 逻辑依据

### 2. TabPatch.dylib（ObjC）

- 构造函数 `objc_getClass("_TtC14PDF_Expert_DMG14TabContentView")`；**找不到则静默降级**
- hook `NSView` 的 `layout`，布局前做幂等约束重写：
  1. 移除 `closeButton → superview.trailing` 约束
  2. 新增 `closeButton.leading == superview.leading + padding`（复用原 padding）
  3. `iconView` / `titleView` 的 leading 常量右移 `(buttonSize + padding)`
  4. 调小 `titleMaxWidthConstraint` 防止长标题压按钮
- 通过遍历约束 item/attribute 动态匹配，不写死索引；悬停/点击/拖拽行为不变

### 3. inject_lc.py（Mach-O 注入器）

- fat binary → x86_64 slice → load commands 空隙插入 `LC_LOAD_DYLIB`
- dylib 安装路径：`~/Library/PEPatch/TabPatch.dylib`（app 外，更新不丢）
- 幂等：已有该 load command 则跳过；header 空隙不足则明确报错

### 4. patch.sh

1. 提示退出 PDF Expert
2. clang 编译 dylib → 拷贝到稳定路径
3. 首次运行备份原主程序到 `backup/`
4. 注入 → `codesign --force --deep --sign -` → `xattr -dr com.apple.quarantine`
5. 校验（`codesign -v` + `otool -l` 确认 load command）
6. `--restore`：还原备份

## 错误处理

- 类找不到 / 约束匹配失败 → NSLog 记录，app 正常运行不崩溃
- 注入器检测已打过补丁 → 跳过（幂等）
- 重签失败 → 中止并自动还原备份

## 已知代价（用户已接受）

- 签名从 Readdle 官方变为 ad-hoc；Gatekeeper 首次可能需右键打开
- 账号制 License 不受影响
- Sparkle 自动更新覆盖补丁 → 重跑 `patch.sh` 即可

## 测试计划

- 启动 app，开 2+ 标签：关闭按钮出现在左侧；点击关闭、悬停高亮、拖拽换位正常
- 长标题不与按钮重叠
- patch.sh 幂等（连跑两次结果一致）；`--restore` 可还原
