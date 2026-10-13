# 决策者审查与复验记录

日期：2026-10-12。结论：**PASS（开发任务验收）**。用户试玩和正式交付批准仍待用户处理，本记录不替代这两项。

## 审查范围

- 实际工作目录：`D:/ConjoinedTwins`。读取主场景、工程配置、六份生产脚本、三关数据、测试脚本、README、启动入口、执行者报告、试玩清单、源码新增 Diff 和哈希清单。
- 通过本次 Controller 提供的证据路径确认 Run ID：`d9136cea-3d0d-4769-a795-d9a46db671fa`；runtime：`92184584fd7d49b4`。模型后端身份和推理变体没有额外核验，仍以执行者报告中的会话声明为准。
- 验收时直接读取交互策略，实际值为 `idle`。执行者此前读取外部策略被拒绝，按默认 work 执行；该历史记录保留。两阶段均未自动打开游戏窗口，不操作桌面、改策略或绕过 Hook。
- 使用 RTK 代理普通 Shell。Serena 当前不可调用，使用定向检索及必要源码读取。
- 非 Git 工程，Diff 表示相对于初始仅有计划文档的新增源码。修复前核对原哈希清单，17 项一致。没有全项目自动快照，不声称验证了所有外部或未知历史变更；原计划文档保留。

## 直接修复与补充验证

右键目标原先在事件处理中查询当前全局鼠标位置。headless 合成视口事件没有更新原生鼠标位置，导致事件坐标与查询值不一致。改用右键事件自身的坐标，并通过场景画布变换转换为地面坐标；无需读取或移动桌面鼠标，也避免缓冲事件处理时使用后续游标位置。

新增 `tests/decision_review.gd`，实例化真实主场景，验证生产输入处理、引擎内合成按键/视口事件、暂停、模式菜单、检查点重开、返回起点和完成后重玩回调。右键同时验证正常坐标与场景平移/缩放后的坐标。合成事件不等于真实设备或可见 GUI 验收。

首次补充测试中，合成按键尚未刷新、复用了事件对象，且全局鼠标查询不能反映合成事件。修正测试适配：等待场景初始化、刷新引擎输入缓冲、使用新的释放事件；随后完成上述右键处理修复。最终测试日志对应修复后的结果，没有将初轮失败冒充通过。

## 实际命令与结果

工作目录均为本项目；以下命令通过 `rtk proxy powershell -NoProfile -Command` 调用，实际使用 Godot `4.7.1.stable.official.a13da4feb`。所有调用同步结束。

```powershell
& "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/ConjoinedTwins" --editor --import --quit --log-file "D:/ConjoinedTwins/tests/decision-import.log"
& "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/ConjoinedTwins" --quit-after 120 --log-file "D:/ConjoinedTwins/tests/decision-startup.log"
& "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/ConjoinedTwins" --script res://tests/headless.gd --log-file "D:/ConjoinedTwins/tests/decision-headless.log"
& "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/ConjoinedTwins" --script res://tests/decision_review.gd --quit-after 180 --log-file "D:/ConjoinedTwins/tests/decision-review.log"
```

- 导入、解析、主场景启动：退出码均为 **0**，未见脚本错误。
- 原机制套件复验：**65 项通过，6012 个模拟步**，最大距离 **220.000030517578 像素**，最大正常帧位移 **6 像素**；结果见 `tests/latest_result.json`。三关通过真实移动与 AI 指令完成，没有为通关瞬移或直接开门。
- 补充套件：**20 项通过**，退出码 **0**，结果见 `tests/decision_review_result.json`。补充检查在有限步骤内结束，运行命令另设 180 帧退出上限。
- 修复后重新导入、启动并运行原机制套件，65 项仍通过。
- 最终源码 Diff 与 SHA-256 清单同步更新；项目无残留 Godot 进程。没有 Git 提交、推送或发布。

## 验收边界

| 层级 | 结果 |
| --- | --- |
| 执行者自测 | PASS：65 项机制断言及导入/启动 |
| 决策者审查与复验 | PASS：源码审查、直接修复、65 项复验及 20 项补充检查 |
| Controller 独立测试 | 未运行：`tests=[]`；上述复验不计为 Controller 测试 |
| 用户试玩 | pending：中文显示、视觉反馈、真实设备输入、操作手感、难度与卡死检查 |
| 可见 GUI | 未运行；执行者阶段记录为 `deferred_by_work_mode`，验收阶段仍遵守不自动开窗口的授权 |
| 正式交付 / 发布批准 | 未授予 |

用户入口：双击 `D:/ConjoinedTwins/启动白盒.cmd`，按 `docs/PLAYTEST_CHECKLIST.md` 独自试玩三关。
