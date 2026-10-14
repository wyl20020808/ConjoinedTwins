# t02 道路充能闸门

Run：`27906b89-1447-4df8-994d-5536ebd0cd02`。当前任务：`t02-charge-gate`；t01 已由配置决策者验收，本轮不重做。分支 `feature/charge-gate`，基线 `4743fa50f3110b1c9ed67ce423c9572cc131db6e`；保留 t01 未提交成果，不提交、合并或推送。

## 实施方案与恢复入口

目标是第一关随机道路之前的独立安全教学。复用历史 `mechanisms.gd` 的 0.8 秒连续充能、条件丢失清零与锁存规则，保留历史白盒文件。道路判定改用真实 `rope.path`、实际绳高及生产绳长比例；两人在接收器左右操作区站位（可交换角色），路径穿过接收器且张紧至少 85%，未被障碍遮断才充能。

教学推进中心停在接收器处，等待无限时长；双方仍用生产固定步移动、跳跃与硬绳长约束。关闭的全宽高门纳入位移扫掠，阻挡而不杀死玩家，不允许跳过或绕出路面穿门。开门后恢复道路推进，随机生成从教学出口后开始。仅生产场景显式启用教学，不改变历史白盒和独立物理夹具的默认行为。机关状态使用值类型，避免生成克隆共享计时器。

计划：

1. 固定生产入口、合法输入路线、反例、暂停、锁存、重试和门扫掠检查，运行缺失功能反例。
2. 最小接入 `scripts/road_charge_gate.gd`、`scripts/road_run.gd` 与 `scripts/road_demo.gd`，复用道路材质、程序几何和音效。无新增大资源。
3. 运行专项与受影响的控制、绳索、碰撞及联机检查；失败按根因修复，不削弱已有断言。
4. 独立只读审查，记录源码绑定凭证，清理辅助脚本并释放 Writer；交配置决策者复核。

任务临时目录：`D:/ConjoinedTwins-task-temp/27906b89-t02-charge-gate`。初始快照 `start.json`，t01 修改前副本 `README.md.before`、`road_demo.gd.before`；原有未跟踪文件均记录 SHA256。Writer：`.git/t02-charge-gate-writer.json`，仅本执行 Session 写入。

裁定：用户已明确方案、范围和验收，并授权常规技术判断；不重复请求技能流程确认。使用实际可用的原生工具，不冒称其他客户端固定模型或工具。可见 GUI 和手感按用户本轮 work 约束延后，即使策略文件当前为 idle 也不操作桌面。

状态：实施完成，专项、完整场景与联机自测通过；独立只读审查整改通过。配置决策者验收待执行，不以只读审查代替其验收。

## 已实施与失败修复

新增 `scripts/road_charge_gate.gd` 与 `tests/road_charge_gate.gd`；改动 `scripts/road_run.gd`、`scripts/road_demo.gd` 与 README。教学接收器位于 3 米处，推进中心固定在此；门位于 7.5–8.1 米处，高 5 米，关闭时参与双方及约束修正位移的连续扫掠。充能按每个物理子步检查实际折线路径与绳高，障碍遮断及接触使进度清零。机关字典随状态克隆深复制，联机状态哈希包含开闭与进度。

首次专项因生产入口缺少教学退出 1（RED）；实施后 32 项通过。追加真实货箱与绕柱反例后 36 项通过。首次已有绳索显示回归失败 2 项：该夹具切到非流式独立物理场景，教学仍启用使推进停在柱子之前。修复为仅流式道路第一关安装教学，原检查未改，随后 8 项通过。控制回归通过，连续碰撞 6 项通过；启动退出 0。

独立审查发现斜绳高度漏判：平面最近点不一定是有效高度的穿过点。先新增失败正例（倾斜高度 28→37），再改为平面圆盘参数区间与高度区间求交；补充 28→38 负例。最终专项 39 项通过。真实路线只使用 -1/0/1 双人轴，记录每步位置、充能及真实绳路；检查无瞬移与超长。

完整场景夹具原来每次走两个固定步，却使用单固定步精度调站位，位置在 ±62/67 之间振荡，反复丢失 85% 张紧条件；充能归零符合要求。调整为到 ±64 后松键，保留全部原断言。完整第一关教学后到达结算，最新凭证 34 段、147 个散布陷阱，奖励、跳跃、落地、过关及绳索表现数据检查通过。

ObjectDB 退出警告仍存在：专项 3 个、完整场景 4 个；verbose 定位到音频 WAV 和播放对象。尝试的音频退出清理未稳定消除，已撤回并恢复原文件字节，不虚报修复。控制夹具重复解析输入事件警告也保留。这些检查仅 headless；画面、真实音效与手感不能据此通过。

Serena：通过已配置的本机 stdio broker 调用 `initial_instructions`、`activate_project` 与 `get_symbols_overview`，首轮均成功；激活实际项目 `D:/ConjoinedTwins`、gdscript。第二次连接 initialize 超时，记录工具限制并聚焦读取源码，未启动或终止 Godot 编辑器。用户声明受管理 LSP 端口 6008，端口声明本身不作为符号可用证据。

第二连接超时后，第三次调用恢复成功，`rope_solver.gd` 符号概览及 `path_heights` 符号正文均可用，确认实际路径高度按各段弧长比例插值。新增教学的首次联机回归为 12/13：随机晃动夹具没有完成教学，原“装入后台段落”断言失败。只补充合法站位输入并在教学时停止夹具跳跃，保留断言。

联机新增教学断言后，教学、同步已通过，但任意截止帧碰巧失败重试，清空了当前段落。实际 UDP 客户端教学后复用已有证书合法路线，并在达到 2400 帧、双方 3 段且运行中时发送真实同步暂停命令，再核对冻结快照；40 秒硬上限及所有原断言保留，新增暂停断言。线程快慢差异子测仍保留旧晃动与重试覆盖；实际 UDP 客户段的随机失败压力覆盖已变更，不混称为同一种验证。

继续诊断发现截止条件等待失败的真实原因还包括重试教学站位过冲：两端状态相同，角色位于 (-29.6,60)/(117,60)，生成未停机但双方不在操作区。修正合法反向回退，并在教学使用 1 倍时间；持续控制仍因网络坐标回显延迟形成往返振荡，再改为每 20 个物理帧点按一次、等待回显，进入有效区后松键保持充能。全部修改限测试驱动，生产移动、网络协议与开门条件未变；不以关闭门判定、直接改坐标或删除断言解决。

最终真实 UDP 联机 16/16 通过：2818 帧、失败重试7次，双方完成教学、指纹一致、未不同步、各加载3段，同步暂停及断线检查通过。此为特定合法点按路线的 headless 证据，不代表持续按键联机手感验收。

只读独立审查：原斜绳 P2 已关闭，夹具整改合理，未发现新增阻塞问题。审查者未跑测、未写文件或操作 GUI；配置决策者需自行选择必要验证。Controller 独立测试 `tests=[]`，用户试玩未运行。下一任务候选为教学与避障组合，本轮先交 t02 验收，不堆叠新机制。

## 最终验证凭证

以下均为执行者本轮实际运行；原生日志保留，退出码如列。

### charge-scope-final

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins\tests\road_charge_gate.gd
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\charge-scope-final.log`；原生进程已结束：`True`。关键行：

```text
PASS 失败重试关闭门并归零进度
PASS 关闭门连续碰撞且不杀死或穿透
PASS 关闭门与充能进度显示
PASS 门前回退调整可恢复开门
PASS 联机状态哈希包含开闭状态
PASS 合法交换角色路线仍开门
PASS 没有主玩法 AI
PASS 下一关不重复首次教学
CHARGE_GATE checks=39 failures=0 legal_axes=true
WARNING: 3 ObjectDB instances were leaked at exit (run with `--verbose` for details).
```

### startup-final

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --quit-after 120
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\startup-final.log`；原生进程已结束：`True`。关键行：

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

```

### controls-final

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins\tests\baseline_controls.gd
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\controls-final.log`；原生进程已结束：`True`。关键行：

```text
PASS 暂停清除触屏
PASS 暂停清除触屏：旧手指拖动不恢复移动
PASS 恢复后无旧移动或旧跳跃
PASS 触屏夹具确实产生移动和跳跃
PASS 失败后共同出发清除触屏
PASS 失败后共同出发清除触屏：旧手指拖动不恢复移动
PASS 联机夹具确实按住键盘跳跃
PASS 联机键盘跳跃不延迟消费触屏点按
WARNING: An input event object is being parsed more than once in the same frame, which is unsafe.
BASELINE_CONTROLS failures=0
```

### rope-final

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins\tests\baseline_rope_view.gd
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\rope-final.log`；原生进程已结束：`True`。关键行：

```text
PASS 合法零轴输入确实产生绕柱路径
PASS 可见绳索质点贴合生产绕障折线
PASS 两端贴合双方腰部
PASS 暂停定格真实绳索
PASS 重试清除绕柱接触并恢复两端
PASS 货箱总高度与碰撞一致且顶部避免共面
PASS 跳跃顶点动画到达半程 P1
PASS 跳跃顶点动画到达半程 P2
BASELINE_ROPE_VIEW failures=0
```

### collision-final

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins\tests\endless_collision.gd
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\collision-final.log`；原生进程已结束：`True`。关键行：

```text
PASS 动态刺高合法跳跃 P1
PASS 高速飞行扫掠 P1
PASS 重试双人合法状态
PASS 动态刺高合法跳跃 P2
PASS 高速飞行扫掠 P2
PASS 重试双人合法状态
```

### scene-bound

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins\tests\random_scene.gd
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\scene-bound.log`；原生进程已结束：`True`。关键行：

```text
PASS 按已证明路线到达结算
PASS 第一关先完成合法充能教学
PASS 出现散布陷阱
PASS 金币飞行补间出现过
PASS 飞行结束后得分栏等于真实分数
PASS 绳子网格逐帧重建且两端贴住两人
PASS 金币、起跳、落地、过关音效都播放过
PASS 重试后换了新种子
SCENE failed=0
WARNING: 4 ObjectDB instances were leaked at exit (run with `--verbose` for details).
```

### online-pulse

命令：

```text
D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:\ConjoinedTwins --script D:\ConjoinedTwins\tests\online_lockstep.gd
```

退出码：`0`；日志：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\online-pulse.log`；原生进程已结束：`True`。关键行：

```text
PASS 联机生产入口启用教学
PASS 联机同步暂停保留已加载段落
PASS 联机推进 2818 帧（失败后重试 7 次）
PASS 两端最终状态指纹一致
PASS 双方通过真实联机充能教学
PASS 服务器未报告不同步
PASS 两端都装入了后台生成段落
PASS 队友断开后本端停止对局并暂停
PASS 断开一方回到单机
RESULT 16/16 passed
```

### 工作区与清理

`rtk git diff --check` 退出 0，日志 `D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\diff-check.log`。分支 `feature/charge-gate`，HEAD `4743fa50f3110b1c9ed67ce423c9572cc131db6e`，暂存区为空；未提交、合并或推送。原有 19 个未跟踪文件 SHA256 全部不变；t01 README 与 road_demo 原件保留，当前新增修改叠加其成果。

源码绑定：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\final-source-hashes.json`；独立审查摘要：`D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\independent-review.md`。复核入口为各测试原生命令及本报告，不需重建任务。

清理报告：删除本任务辅助脚本、探针、重复成功日志和中间路线文件，共 60 项；释放本任务 Writer。只清理任务专属目录内明确创建的文件，无递归删除、无 junction/symlink 穿越。保留最终日志、最终合法路线、必要 RED/失败根因记录、Serena 实际结果、初始保护快照、t01 原件和独立审查摘要，用于恢复和复核。完整清单见 `D:\ConjoinedTwins-task-temp\27906b89-t02-charge-gate\cleanup-receipt.json`。本任务启动的 Godot/UDP/辅助进程均已结束；受管理 LSP 保留。未能清理项：无。用户文件、源码、正式资产、历史证据及可再生缓存未删除。

交付状态：本轮执行者自测与只读审查整改已完成，交配置决策者验收；Controller 独立测试未运行（tests=[]），用户试玩未运行，GUI/真实设备输入/画面和手感 deferred_by_work_mode。当前目标完成增量为 t02 独立教学；下一步待本轮决策者判定后推进教学与避障组合。

收尾独立只读核对：新版联机全部断言与16/16日志吻合；14个最终源码哈希、19个保护文件哈希重新计算全部吻合；Writer不存在，实际目录与保留清单一致，60项删除对象均不存在，无本任务散落探针。审查者未跑测试，未写文件；仅证据绑定与清理核对通过，不替代配置决策者验收。
