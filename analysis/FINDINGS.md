# FINDINGS — TabContentView 布局逆向（Hopper Disassembler CLI 自动化）

分析对象：PDF Expert 3.13.4 主程序 x86_64 slice（`build/pe-x86_64.bin`，12MB，37394 procedures）
工具：`/usr/local/bin/hopper -e <slice> -Y <绝对路径脚本.py>`（注意：**-Y 必须用绝对路径**，相对路径会报 `Cannot execute Python script`；脚本结尾 `os._exit(0)` 让 Hopper 自动退出）
产物：`analysis/hopper_dump.txt`（目标方法 + sub 函数合并导出，384K；由 tools/hopper_dump.py 生成）

## 逐项结论

1. **closeButton 约束创建位置**：`sub_1001008c0`（TabContentView 公共初始化，由
   `initWithCoder:` 调用，dump1 第 42 行 `sub_1001008c0(rdi)`）。该函数含数十处
   `constraintsWithVisualFormat:options:metrics:views:` 调用（深分支状态机：选中/hover/linkMode 等）。
   另外 `initWithFrame:` 是**未实现的**（`_swift_stdlib_reportUnimplementedInitializer` + `ud2`）→
   所有真实标签都经 NIB 的 `initWithCoder:` 创建。

2. **VFL 字符串确认**：二进制 __cstring 中存在
   - `H:[closeButton(==buttonSize)]-rightPadding-|`（宽度锁定 + 右缘钉住）
   - `H:[closeButton]-|`（自然宽度 + 右缘钉住，某状态分支）
   - `V:[closeButton(==buttonSize)]`（正方形尺寸）
   - metrics 字典 key：`buttonSize`、`rightPadding`、`leftPadding`

3. **buttonSize 常量值**：VFL metrics 字典在运行期传入（寄存器间接），静态值未直接可读。
   → dylib 不硬编码，运行期从 width 约束或 intrinsicContentSize 读取。

4. **iconView / titleView 的定位**：`titleToIconConstraint`、`titleMaxWidthConstraint`、
   `closeButton`、`iconView` 在 `sub_1001008c0` 开头仅初始化为 nil（dump2 第 24–27 行），
   真正创建在后续分支里；反编译为寄存器级，字典 key 未直接渲染。
   → dylib 采用**双方向动态匹配**（leading pin 可能是 sub-first 或 sup-first 两种方向），
   并内置 fallback（icon 若无 leading pin 则链到 closeButton.trailing + padding）。

5. **titleMaxWidthConstraint 机制**：ivar 存在（dump1/2 确认），标题宽度上限，需按 shift 缩减。

6. **TabContentView 是否 override layout**：nm 符号表无 `layout` → 我们包装的是 NSView 的
   `layout`，安全。（`class_addMethod` 失败分支也已处理未来版本自带 override 的情况。）

7. **其他风险点**：
   - 约束可能在状态切换时整体重建 → hook 放在 `layout`（约束变更必然触发布局），幂等检查用
     约束 identifier，重建后自动重新应用。
   - `onCloseButtonClick:` 转发 `sub_100100290(self,_cmd,arg2,0x140)`，与布局无关，不动。
   - `TabView.updateConstraints` → `sub_10062cdf0`（标签条级别，非单标签，不需要动）。

## 结论

Task 3 的四个动态匹配假设全部成立且更稳：
① trailing pin 存在且可识别（两种方向都匹配）；② width 约束可读出 buttonSize；
③ icon/title leading 常量可位移（双方向 + fallback）；④ titleMaxWidth 可缩减。
静态 padding 值不可得 → 运行期读取（`fabs(trailingPin.constant)`），符合计划。
