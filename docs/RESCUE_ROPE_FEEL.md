# 救援绳索与握绳表现（限时尝试）

日期：2026-10-20。分支：`fix/rescue-rope-feel`（从 `test@27ea45b` 新建）。用户限定 20–30 分钟的尝试。

## 问题

- 吊挂时绳子的引导线是"掉下的人 → 队友"的一条直线。绳子绷直时质点直接贴合这条线，所以会斜着穿过崖壁和地面，不是竖直挂在崖沿下。
- 单摆长度约束作用在脚部，而绳子挂在腰上，两者对不上。
- 爬上阶段，人从吊挂点直线插值到落脚点，再加正弦起伏，像斜着飞上去，没有顺着绳子爬。
- 双手不握绳。

## 改动

- `road_run.gd`：
  - 吊挂者腰部低于崖沿时，引导线改为"腰 → 崖沿（地面高度）→ 队友腰"。绳子从腰部竖直上到崖沿，再沿地面到队友，重力方向正确。
  - 单摆长度约束改为作用在腰部挂点。
  - 爬上路径分两段：前 55% 顺绳竖直升到崖沿外侧，后 45% 翻过崖沿走到落脚点。
  - 缺少崖沿信息时（旧数据或测试构造）沿用原逻辑。
- `journey_view.gd`：`sync_rescue_hands` 在战斗视图之后，用已有的双臂 IK（`reach_hand`）把手放到绳上：
  - 被救者双手握腰部以上 0.5–1.0 米的绳段，随拉动进度交替倒手；
  - 拉绳者双手握身前 0.45–0.8 米的绳段。
  - 只改表现，不改模拟。

## 验证

- `check_journey_performance.py` 26 项通过，报告在 `~/ConjoinedTwins-perf-reports/rescue-rope/`（`rescue_animation` 加兜底之前跑的；兜底只影响缺少崖沿信息的数据）。
- `journey_rescue_transition`、`journey_rescue_hud`、`journey_failure_presentation`、`rescue_animation`、`interaction_loading_rescue` 均 0 失败。
- 截图：`builds/rescue/shots/sheet.png`，依次为吊挂、拉动、爬升、翻上。
  - 截图工具冻结了世界，落脚点搜索找不到地方，所以爬升阶段的落脚点是手动给的；游戏内由 `rescue_anchor` 决定。

## 未完成

- 手部只看了远景截图，握绳的准确度和倒手节奏需要真人试玩确认。
- 救援镜头会被路边树叶遮挡（原有问题），没有处理。
- `rescue_animation` 测试在 `test` 上本来就会报 `rescue.rim` 脚本错误（测试构造的数据缺字段），不是本次引入，也没有修改测试。
