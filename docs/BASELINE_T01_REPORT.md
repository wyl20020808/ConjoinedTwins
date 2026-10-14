# t01 当前可运行基线

Run：`27906b89-1447-4df8-994d-5536ebd0cd02`。任务分支 `fix/playable-baseline`，基线 dev / HEAD `4743fa50f3110b1c9ed67ce423c9572cc131db6e`；未提交、未合并、未推送。执行者自测与独立只读审查通过，等待配置决策者验收；不宣称整体旧测试全绿或设备试玩通过，不自行跳到 t02。

## 当前目标与恢复

复用原 Run 检查点 `context-checkpoint-98d75bb57210b2a9ee04492cf69aeabd2c9c2a6ec9e790f03f8b626377892dad.json`，任务仍为 t01。检查点所在原 Run 目录未修改。交接中的 task-ledger.json 未找到，不能当作已完成记录。Controller PID 48640 仍管理本 Run，`tests=[]`；它不构成独立验收测试。唯一源码 Writer 为本执行 Session，使用 `.git/t01-baseline-writer.json` 排他登记，收尾已释放。独立审查代理只读，无写入者竞争。

初始10个未跟踪 UID/旧结果均逐文件 SHA256 复核不变，详见外部证据 `start.json` 与 `final-source-receipts.json`。无暂存、覆盖或删除无关文件。受管理 GDScript LSP 127.0.0.1:6008 经 Serena initial_instructions、activate_project 和实际符号读取确认可用；未另起或终止编辑器。

## 实际改动

- `clear_controls()` 清除触屏手指、拖动与跳跃，解决运行中重试及暂停立即恢复残留控制。原缺陷回归9项失败，修复后通过。
- 联机每帧先消费触屏点按，避免键盘跳跃条件短路造成延迟消费。合成输入回归先失败1项，再通过；只输入Godot内部事件，不操作系统输入。
- 货箱本体、警示圈、顶板上沿为2.90、2.98、3.00米，最高点与碰撞一致，避免共面顶面。原可信高度断言从失败转为通过。
- 四份新基线检查覆盖控制、真实绳索显示/货箱/动画、落桩、三难度三关合法路线；旧断言未改。
- README按实际入口核对随机地图、联机和单角色触屏，修正15米/秒手动速度、12.5/14.75/16.5米/秒关速、21.6米路面、±10.5米边界、随机重试、96奖励槽、168米后台预加载、麻绳视觉与碰撞规则及历史流程措辞。

## 验证结论与边界

合法键盘路线：种子4242，三难度三关共9组到达结算，每轴严格-1/0/1、非法输入0、绳长越界0，金币228–336；记录输入/位置/路径摘要哈希，没有保存原始逐帧回放，不能称独立复放。现有random_levels另外核验360候选与18整关运行；详见最终凭证。

本机隔离UDP中继和两个生产场景：最终13/13、2734帧、命令同步及周期/最终指纹一致，无服务器不同步。指纹覆盖生产sync_hash定义的字段，不是所有内部状态的完整比较。并行路线负载下曾仅推进2044帧未达2400帧/25秒门槛，失败保留为online_lockstep-parallel-deadline；隔离本任务负载后原断言通过，未改超时断言。

隔离联机时执行者暂停本任务路线进程，导致random_levels一项墙钟耗时计入暂停77秒而失败；360候选与18路线当次均通过。保留random_levels-suspended-timing原失败，完整串行重跑原检查，不修改断言或耗时门槛。

绳索显示检查核对首个真实绕柱路径、质点清障、双方端点、暂停定格和重试清理；random_scene另核对整关逐帧网格及端点。显示验证不代替真实渲染。落桩6时机中5次空中落入桩占地、6次挂绳，长度及低于柱顶时逐段清障错误0。旧夹具十四步分离在当前手速下已拉满，新增七步分离仍有余量，旧断言原样保留。

连续碰撞双方6项通过；状态生命周期6项通过；t04_edges覆盖双方交换、紧绳/松绳、高货箱/柱、护盾及前后奖品站位。旧t04结算、双方确认、关卡推进等断言通过，不能把其后脚本错误掩盖为完整通过。

random_scene最终`SCENE failed=0`、退出0，但退出时有2个ObjectDB实例泄漏警告，未确定对象归属；它不阻碍本轮路线，但不能宣称退出完全无警告。

用户明确work约束优先于策略文件当时idle值。可见GUI、真实键盘/触屏设备、互联网联机、Mac/iOS实机及用户手感：`deferred_by_work_mode` / 未运行；未生成或更新包。

## 旧检查失败单列

- t01退出1、3项失败：双方旧Jump动画名契约（当前Roll替代）、旧松绳青色契约。新增双方跳跃顶点动画半程检查通过；货箱真实偏差已修复。
- t02退出1、8项：靠拢6步未达旧8步计数（真实计时增量0）；随机接触160未达200覆盖门槛；旧有余量落桩夹具实际已拉满（新夹具补证通过）；3项已废弃cable_parts/颜色显示契约；固定每4段中央柱；旧固定走廊越当前边界。独立长度、穿柱、解围与重复接触审计通过，不把旧检查改判通过。
- t04原夹具9项奖励资源失败，固定比例方向与布局不代表合法随机路线；异步新局尚未装入奖励时读layout[0]产生SCRIPT ERROR。停止仅本任务Godot，退出15，属中断失败。原结果文件未覆盖，必要奖励/分关检查另由现有边界与生命周期检查补证。
- 早期两次240秒运行器超时不是生成失败或通过；扩大运行器等待上限后完成新验证，不修改可信检查。

## 独立审查与下一项

独立baseline_review只读代码审查最终通过，未独立跑测试；详见证据review.md。配置决策者仍需据此验收，Controller只收集证据。通过后再进入下一轮候选双人充能闸门；未重复开发现有随机、联机或触屏系统。

## 清理报告

已删除本任务README修改脚本、串行复测辅助脚本、4个被最终结果替代的中断日志/凭证，释放Writer。保留最终命令引用的测试快照、运行器、最终日志/结果、红绿对照、并行门槛失败记录及源码/保护哈希，作为可复核结论集；未为保留证据修改忽略规则。未能清理项：无；未确认归属的历史文件保留。所有本任务Godot已结束，后台路线/联机运行器已完成；本收尾脚本同步退出。受管理LSP和Controller保留。无递归删除、无源码/资产/历史证据删除。详情：外部证据cleanup.json。

## 验证凭证

证据目录：`D:\ConjoinedTwins-task-temp\27906b89-t01-baseline`。`final-source-receipts.json`绑定最终运行源码、保护哈希和每项实际命令；历史显示输入检查与最终规则源码的关系见其中tested_scope。测试输出仅重定向到任务证据目录，不覆盖项目历史结果。

表尾红灯及排程失败为当时执行的对照记录，不是最终源码结果；脚本路径当时相同，脚本随后扩充，红灯日志保留。最终源码绑定不倒签给修复前测试。

| 检查 | 实际命令 | 退出码 | 日志 | 关键结果 |
| --- | --- | --- | --- | --- |
| startup | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --quit-after 120` | 0 | [startup.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\startup.log>) | Godot 4.7.1；无解析错误 |
| baseline_controls | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_controls.gd` | 0 | [baseline_controls.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_controls.log>) | BASELINE_CONTROLS failures=0 |
| baseline_rope_view | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_rope_view.gd` | 0 | [baseline_rope_view.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_rope_view.log>) | BASELINE_ROPE_VIEW failures=0 |
| baseline_landing | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_landing.gd` | 0 | [baseline_landing.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_landing.log>) | BASELINE_LANDING landed=5 hooked=6 geometry_errors=0 passed=true |
| baseline_random_routes | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_random_routes.gd` | 0 | [baseline_random_routes.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_random_routes.log>) | BASELINE_RANDOM failures=0 |
| random_levels | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\random_levels.gd` | 0 | [random_levels.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\random_levels.log>) | 72项 PASS |
| random_scene | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\random_scene.gd` | 0 | [random_scene.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\random_scene.log>) | SCENE failed=0 |
| online_lockstep | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\online_lockstep.gd` | 0 | [online_lockstep.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\online_lockstep.log>) | RESULT 13/13 passed |
| endless_collision | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\endless_collision.gd` | 0 | [endless_collision.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\endless_collision.log>) | 6项 PASS |
| short_rope_t05_state | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t05_state.gd` | 0 | [short_rope_t05_state.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t05_state.log>) | 6项 PASS |
| short_rope_t04_edges | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t04_edges.gd` | 0 | [short_rope_t04_edges.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t04_edges.log>) | 48项 PASS |
| short_rope_t01_headless | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t01_headless.gd` | 1 | [short_rope_t01_headless.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t01_headless.log>) | RESULT failures=3；cargo_model_height_m=3.0 |
| short_rope_t02_headless | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t02_headless.gd` | 1 | [short_rope_t02_headless.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t02_headless.log>) | 8项失败，分类见下文 |
| short_rope_t04_headless | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t04_headless.gd` | 15 | [short_rope_t04_headless.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\short_rope_t04_headless.log>) | 9项固定路线失败；layout[0]越界后停止本任务进程，退出15 |
| baseline_controls-red | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_controls.gd` | 1 | [baseline_controls-red.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_controls-red.log>) | BASELINE_CONTROLS failures=9 |
| baseline_controls-online-red | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_controls.gd` | 1 | [baseline_controls-online-red.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\baseline_controls-online-red.log>) | BASELINE_CONTROLS failures=1 |
| online_lockstep-parallel-deadline | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\online_lockstep.gd` | 1 | [online_lockstep-parallel-deadline.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\online_lockstep-parallel-deadline.log>) | RESULT 12/13 passed |
| random_levels-suspended-timing | `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\random_levels.gd` | 1 | [random_levels-suspended-timing.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\random_levels-suspended-timing.log>) | 暂停计入证明耗时77428ms；RANDOM failed=1；原失败保留 |
| 工作区及保护核对 | `git diff --check`；`git branch --show-current`；`git rev-parse HEAD`；SHA256/进程核对（finalize.py） | 0 | [git-audit.log](<D:\ConjoinedTwins-task-temp\27906b89-t01-baseline\git-audit.log>) | protected=10/10 unchanged；index=empty；owned_godot=0；managed_lsp保留 |
