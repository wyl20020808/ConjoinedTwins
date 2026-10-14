# t05 同步踏板独立教学实施报告

## 身份与恢复入口

日期：2026-10-14。沿用 Run `1899707b-57d1-433f-a67c-ce96f314d04e`，任务 `t05-sync-plates-tutorial`。分支 `feature/charge-gate`，HEAD `4743fa50f3110b1c9ed67ce423c9572cc131db6e`；没有提交、切换分支、合并、推送或发布。用户本轮要求直接实施，覆盖旧“只规划”范围。

保护前轮未提交成果：起点保存 497 个文件的 SHA256，以及本轮修改文件的精确副本；对比起点只有明确列出的 8 个原有文件变化。新增两个 GDScript 文件和本报告。起点源码绑定 `0ed2899e4e095618f162465f26f0d2c58a9bd1ce01b51b4121a1fa24f9433e6b`；当前生产绑定 `de08fad8b7ceb94cc35eafe05997e3838348ddda327db5a26a9ac65c42ee5ae0`。

证据根目录：`D:/ConjoinedTwins-task-temp/1899707b-t05-sync-plates/`。`start.json`、`before/` 为恢复材料；`final-evidence.json` 登记命令、环境、退出码、日志 SHA256、脚本 SHA256、18 份路线及 UDP 痕迹。唯一 Writer 使用原子独占创建 `.git/t05-sync-plates-writer.json`，归属本 Run、本 Session；收尾释放，结果见 `closeout.json`。未重建或修改 Controller 账本。

Serena 已实际调用 initial_instructions、activate_project，再成功读取 GDScript 符号。复用管理方提供的 127.0.0.1:6008 headless LSP；未启动、终止或重启编辑器。策略文件读到 idle，但按用户明确 work 约束执行；未操作桌面。

## 实际改动

- 新增 `scripts/road_sync_plates.gd`：两板中心横向 ±2.25 米、纵向 14.5 米，圆形有效半径 0.9 米，门前缘 19 米。两人各占一板且均在地面，连续 0.35 秒开门；互换板位有效。未完成时任何失效条件归零，开启后锁存。
- `road_run.gd` 在首关原充能教学之后安装踏板教学，复用门队列、等待推进、全宽门连续碰撞、回收和坐标重定位。地面判断使用生产支撑、起跳前后高度和垂直速度；未更改角色移动、绳长、碰撞或随机池。
- `road_templates.gd` 两个路线入口均分派踏板站位控制，仍只输出合法离散键盘轴。现有捕获、克隆、snapshot、sync_hash 和源码绑定包含踏板类型、占用、计时和开闭状态。
- `road_demo.gd` 复用材质、几何和开门音效，显示圆板独立占用、同步进度、地面站位提示及开启反馈。增加逐网络帧执行完成信号，让审计覆盖批量消费的每一帧。
- 新增 `tests/road_sync_plates.gd`；原充能、组合、随机场景和联机测试适配两教学的顺序与独立状态，没有删掉原碰撞、绳路、奖励、段落或断线断言。测试证据输出改用本轮环境路径，未覆盖历史 t03 证据。
- 更新 README 首关内容与本报告入口。音频测试收尾在完成断言后停止播放器、释放 stream，再释放场景；不改变生产声音或玩法。

## 自测与边界

先写不存在模块及反例，RED 为 exit 1。随后实现规则与生产接入，修复路线入口遗漏；保存失败日志。41 个固定步不足 0.35 秒不开门，第 42 步开启。单板、同板、腾空、半径外、离板分别使计时归零；交换角色可完成。

最终教学专项 50/50。三难度 × 三种子（4242、812208、20261014）× 正常/角色交换共 18 份 JSONL，6144 步。从落盘文件读取输入，在新生产 Run 逐固定步复放完整 snapshot 一致；同时检查合法轴值、位移上限、真实绳路限长、关闭门前位置及开启事件顺序。路线达到首个随机段起点之后，但为隔离教学关闭生成；种子记录不代表九份随机地图已全程验收。

真实生产场景另行启用后台生成，按充能、踏板、随机组合顺序到达结算，加载 34 段、147 个散布陷阱；真实绳网端点和音效通过。关闭踏板门跳跃不能穿越，可用合法键盘回撤、调整站位、开门并退出回收，无站位死锁。暂停冻结占用/计时，起跳立即归零，落地重新计时；重试清空两种教学与旧触屏输入，后续关卡不重复教学。

重定位专项使用单独世界坐标夹具，验证踏板、门世界位置、ID 和计时不变；该夹具不作为合法路线或无瞬移证据。18 条路线不直接赋角色坐标。

受影响充能组合重新生成当前绑定证书，三难度 × 三关 × 三种子共 27 组，97/97；教学顺序断言现在明确包含充能、踏板、组合。奖励去重、回收、克隆、重定位、暂停及重试保留验证。另运行原移动、落地、真实绳显示、组合显示专项。

真实本机 ENet UDP 中转服务器加两个生产客户端：19/19。两端每一网络帧 step/report 后记录，按相同 frame 配对。最终完整文件核对 2712 个共同帧（frame 5–2716）、无重复、零状态差异；占用、未完成同步计时、开门、暂停及重试清板均覆盖。最终摘要在重试前打印 2706 帧，完整文件另含收尾生命周期帧，因此数量不同。共同帧包含暂停帧，不能解释为 2400 个运动帧。

联机修复的是测试暂停时序：原先在危险出口等待帧数，暂停命令到达前角色已失败。最终在共同帧 618、组合刚开门的安全站位（distance 620、running）通过生产命令队列请求暂停，再验证冻结和重试；未改变生产物理、瞬移或关闭碰撞。`online-verified.log`、`online-final.log` 的 17/19 历史失败保留。

主要最终日志（命令、退出码及 SHA256 详见各同名 receipt 和总清单）：

| 脚本 | 日志 | 退出码 | 关键结果 |
| --- | --- | --- | --- |
| tests/road_sync_plates.gd | sync-audio-clean.log | 0 | SYNC_PLATES checks=50 failures=0；18 条 replay=true |
| tests/road_charge_gate.gd | charge-clean.log | 0 | CHARGE_GATE checks=39 failures=0 legal_axes=true |
| tests/gate_combinations.gd | combinations-regression.log | 0 | GATE_COMBINATIONS checks=97 failures=0 |
| tests/random_scene.gd | random-final.log | 0 | SCENE failed=0；settlement、34 段 |
| tests/online_lockstep.gd | online-safe.log | 0 | RESULT 19/19 passed；paused=true retry=true equal=true |
| tests/baseline_controls.gd | controls-regression.log | 0 | BASELINE_CONTROLS failures=0 |
| tests/baseline_landing.gd | landing-regression.log | 0 | landed=5 hooked=6 geometry_errors=0 passed=true |
| tests/baseline_rope_view.gd | rope-regression.log | 0 | BASELINE_ROPE_VIEW failures=0 |
| tests/gate_combinations_view.gd | combinations-view.log | 0 | GATE_VIEW failures=0 |

Godot 命令统一为 `D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:/ConjoinedTwins --script <表中脚本>`。`run_check.py` 包装器保存环境、日志、退出码并等待进程结束，普通检查上限 240 秒；本轮最终检查无超时。

警告单列：最终三份教学/充能/随机场景日志已无音频退出警告；旧警告日志保留。既有控制夹具仍有“同帧重复解析输入事件”警告；组合显示专项有 2 个 ObjectDB 退出警告。它们的退出码为 0、断言通过，不称为无警告检查。WAV/Playback 诊断原始日志保留，未屏蔽日志或改引擎设置。

## 审查与后续

执行者自测：以上实际 headless 结果。独立只读审查席 `/root/t05_review`：代码审查通过，Critical/Important 均无；最初联机生命周期问题已复核关闭。审查核对实际源码、起点副本、18 份落盘文件和完整 UDP 痕迹，没有复跑长 Godot。审查提出同步教学日志音频警告后，执行者补齐退出清理并重新得到 `sync-audio-clean` 50/50；没有把执行者自测算作决策者验收。

配置决策者验收：待原 Controller 顺序调度；Controller 独立测试 `tests=[]`。GUI、真实设备键盘与用户试玩未运行，可见 GUI 为 `deferred_by_work_mode`。本机 UDP 不代表互联网或跨设备联机，固定教学证明不代表全部随机内容公平性。

本轮实现和证据交回原 Run 验收，普通增量不结束长期目标。验收通过后沿用 Controller 已配置下一任务继续；本轮没有加入踏板随机组合、敌人或新主题，不抢先覆盖后续范围。

## 清理报告

最终清理实际结果登记 `closeout.json`，连同进程和 LSP 检查日志 `closeout.log`、源码/工作区审计 `evidence-audit.log` 留存。本任务临时产物始终在项目外任务目录，没有散落源码或项目根目录；两个新脚本和报告为正式成果。

保留：起点清单和恢复副本、最终日志/receipt、18 份输入复放、27 组组合证书与序列、UDP 共同帧、独立审查摘要、被审查引用的历史日志及失败、可复现检查/审计脚本。前轮五份规划复核材料及所有前轮源码、资产、审计证据原样保留。管理方 LSP 编辑器保留。

删除范围只限本任务自身的重复中间材料和已释放 Writer；确切路径、释放字节数、未清理项及归属核对见 closeout 清单。未删除历史失败、他人文件、源码、正式资产、共享缓存或管理方进程。最终检查进程已退出；不以进程消失替代测试通过。
