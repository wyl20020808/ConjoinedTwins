# 战斗密度、窄桥与 Boss 分阶段存档

任务分支：`fix/combat-rescue-checkpoints`。起点为本地 `test` 的 `d64a3b864f30ba8707e7a8d48fd610350c0f807f`。工作区为 `D:/ConjoinedTwins-task-temp/combat-rescue-checkpoints`，原工作区的未提交改动保持原样。用户于 2026-10-23 明确授权提交本任务并合并本地 `test`；不推送远端，不生成发布包。下述未通过的验收项仍保留。

## 行为调整

- 普通怪物及 Boss 召唤的小怪血量提高约 50%。35 点血量取整为 53；Boss 本体血量不变。
- 每片三波怪物潮减少十只：前两波各减三只，末波减四只。机关附近小队的目标数量从 2/3 只提高到 4/5 只；仍须通过安全出生点检查，不把怪物塞进缺口、实体或合作门区域。
- 单道中央、边缘窄桥宽度从 44 增至 108 单位，双道和三道地形保持原宽度。仍保留坠落与救援规则。
- 救援结束的回镜使用每秒 12 的指数收敛，专项检查要求一秒内回到正常镜头；救援中的镜头不变。
- 第一章进度条增加独立 Boss 终点段。出场前显示 `???`，出场后显示 `枯根巨像 Boss`。其他章节及战斗训练保留原分段。
- 右上角原“武器”标题显示当前武器名称；换枪、空手时同步刷新。
- 暂停或失焦时持续冻结探索、战斗两层音乐；重新聚焦仍尊重游戏暂停状态。音频状态更新不再依赖是否产生新的模拟画面。
- Boss 进入第二、第三阶段时保存完整对局快照，死亡后恢复双方血量、枪械、子弹、位置、Boss 血量、阶段和场内状态；胜利后也保存。复用已有对局内检查点，不新增跨进程磁盘存档。
- 为控制新增机关小队的寻路成本，静止网格采样改用等价的矩形闭区间点判定，并复用五个脚底偏移。专项逐点对照原判定，未放宽地面与实体碰撞条件。

## 验证与证据

证据目录：`D:/ConjoinedTwins-task-temp/combat-rescue-evidence`。日志与性能报告保存在工程外，不入库。

- `tests/journey_playtest_balance.gd`：血量比例、每片怪物潮减十只、单道桥偏移容错与边界、寻路采样等价性、持续暂停与失焦音乐、武器名称、Boss 分段文字、两次换阶段恢复非默认资源、胜利存档、回镜时间。
- `tests/journey_boss.gd`：674 项检查通过，包含原 Boss 技能与本轮阶段恢复断言。
- `tests/journey_monsters.gd`：456 项检查通过，按新血量核验击杀子弹数与血条比例。
- `tests/journey_narrow_routes.gd`：按新单道宽度逐点核验地面，保留多通道与正常输入过桥、绳长约束检查。
- 最终串行 `python build-tools/check_journey_performance.py`：27 项中 26 项通过，源码哈希在检查期间保持一致。唯一失败为 `journey_runtime_budget` 的物理回调追赶门槛，整套状态为失败；无脚本或引擎错误、无泄漏失败。其余怪物、窄桥、碰撞、绳索、资源生命周期、救援等项目通过。
- 原生检查入口补上项目已有的 `--chapter=0`，避免停在主菜单等待玩家。救援检查夹具关闭章节开场，并新增全黑截图失败断言。原先的超时与开场干扰记录仍保留，不当作通过证据。该夹具调整发生在完整性能回归之后，另补跑修改后的无界面救援检查；游戏源码与完整性能报告记录的哈希一致。
- 修改后的救援夹具补跑 8 次无界面循环通过；最终资源导入退出码为 0，无错误。`git diff --check` 通过。检查产生的两份无关 UID 已清理，本轮新增测试的 UID 保留；临时基线对照工作区已移除，其证据仍在工程外目录。所有本轮测试进程均已退出。
- `native-rescue-verified/summary.json`：Vulkan Forward+ / RTX 4080 SUPER 完成 16 次救援，行为断言、截图非黑检查通过，无对象泄漏警告；已人工查看 `rescue.png`、`returned.png`，后者正常显示回归道路的镜头、武器名和终点问号。整套原生门槛仍为失败，因为 Vulkan Loader 报告两份本机 Overwolf 配置文件缺失（`D:/Software/overwolf/0.305.0.9/ow-vulkan-overlay64.json`、`ow-graphics-vulkan64.json`）。未修改系统或驱动配置，也未过滤这些错误。

未修改的 `test` 在本机对照中也未通过“180 画面循环物理回调 170–270 次”门槛：实际 538 次。本任务最终串行回归为 540 次；双固定步模拟均值分别为 12.643 ms、12.545 ms。本轮新增的寻路预算超限经等价采样优化后消除，最终最慢位置 p95 为 4.648 ms，门槛仍为 5 ms。不能因此将整个性能门槛标为通过；完整记录见 `performance-final/summary.json`、`baseline-runtime.json` 和 `baseline-runtime.log`。没有通过调整计时、阈值或停止其他进程来制造通过结果。

执行者自测、代码审查、原生渲染检查与用户真实双人试玩分别记录。Controller 独立测试未运行（`tests=[]`）；未进行真实键盘操作或用户试玩，也未更新安装包、网页发布或 Mac 包。

## 试玩入口

双击本工作区的 `启动归航Demo.cmd`。Boss 专用预览复用 `build-tools/boss/play_intro.gd`，例如在本工作区运行：

```powershell
& 'D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe' --path 'D:/ConjoinedTwins-task-temp/combat-rescue-checkpoints' --script res://build-tools/boss/play_intro.gd
```

该入口使用本任务源码。本地 `test` 集成不代表已发布或已通过真人试玩。
