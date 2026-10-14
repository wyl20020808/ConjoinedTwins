# t07 双门合作接力实施计划

> 执行方式：沿用原 Controller 顺序调度及配置决策者验收。实施者使用 executing-plans，逐项完成；本次仅规划，不执行源码改动、Git 提交或任务账本写入。

**目标：**将已学充能门和同步踏板门组成可等待、可回撤、可交换角色的顺序接力段，接入生产生成与验证；普通增量通过后继续滚动开发。

**架构：**复用两种机关字典及 road_run 的 charge_gates 队列。每个接力段携带两个独立门实例，仍按最近未开门推进与锁存；不建立第二套物理、机关计时或联机状态机。

**技术：**Godot 4.7.1、GDScript、生产 1/120 秒固定步、现有后台证书生成、UDP 共同帧同步。

**需求来源：**原 Run `1899707b-57d1-433f-a67c-ce96f314d04e` 的 `t07-cooperative-relay-and-continue`，恢复检查点 taskIndex=2；参考 README、INITIAL_DEVELOPMENT_PLAN 的合作与统一运动要求、SYNC_PLATES_COMBINATIONS_T06_REPORT 的最新决策补充。需求与本计划一起交原 Controller，不重建历史任务。

## 当前事实与范围

- 当前分支 `feature/charge-gate`；已有未提交源码、教学模块及测试，均属于应保留的依赖成果。开工不能切换分支、暂存或重置这些成果；沿用原任务连续开发及唯一 Writer。
- 当前源码已有充能教学、踏板教学、charge_cargo、sync_cargo；`make_block()` 返回单门，`install_block()` 只识别 `block.gate`。没有读到生产双门接力实现。
- `select_charge_gate()` 按 receiver.y 选最近未开门；capture_state、clone_state、sync_hash 已覆盖门队列。多门视觉节点和独立开启提示已有实现。
- `extra_hazards()` 的现有单门全宽保护范围为局部 y=0..350；接力不能直接沿用，否则第二个操作区可能混入陷阱。
- SEGMENT=840、MANUAL_SPEED=300、LINK_LIMIT=146.6。当前简单/普通/困难基础推进速度为 250/295/330 单位每秒；旧记忆中的 8 米/秒不能用于本轮预算。
- t05/t06 持久账本均为 decisionAccepted=true、userAccepted=false、testsPassed=false。不重新执行已验收历史任务。t06 历史速度结果事故仍未恢复；不把其旧文件作为新凭证。
- 用户明确要求不碰桌面。虽然策略文件记录 idle，本轮仍按该明确限制执行；GUI、真实设备输入和用户试玩为 deferred_by_work_mode / 未运行。
- 已实际调用 Serena initial_instructions、activate_project，成功取得 GDScript 方法概要与函数体。保留管理方 LSP 127.0.0.1:6008；不另起、不终止编辑器。

## 方案选择

采用一个固定 840 单位段内的双门列表：兼容原单门字典，仅在新路线使用 gates。相比拆成两段，它能保持一次抽签、一个完整出口证书；相比新增机关管理器，它避免重复已有锁存、回收和同步逻辑。

路线名称拟定 `charge_sync_relay`。段内局部布局初值如下，实施时只依据合法输入反例调整参数，不放宽绳长或关闭碰撞：

1. 充能接收器 y=120，左右区域由 ChargeGate.make_tutorial() 整体前移 60 得到；第一道门 y=210。
2. 第一门之后至第二接收器之间保持全宽空地，第二踏板接收器 y=480，踏板模板整体前移 190，第二道门 y=570。
3. y=582..840 为退出、归队区；两人回到 x=-25/+25、y=推进中心，落地、绳路无挂点后才确认出口。
4. 本轮接力段整段禁止追加散布陷阱与封路巨岩。不叠货箱、敌人或周期伤害，先验证两种协作站位的转换。
5. 两门各自拥有 charge/open/occupied 和稳定 ID。第一门锁存后第二门才成为当前操作目标；不共享进度、不回关、不累计重复开启奖励。

## 全局约束

- 双方原始输入轴仅 -1/0/1，斜向归一化由生产 step 处理；路线验证器不接管玩家。
- 充能门沿用真实绳路、85% 张紧、0.8 秒和高度判定；踏板沿用两板地面连续 0.35 秒、中断归零及角色交换。
- 关闭门仍阻挡身体及绳路，跳跃不能绕过；每道门分别停止自动推进并允许前后调整、等待和回撤。
- 从生产出生状态实际抽签、生成、安装、固定步运行；不能只测试手动塞入模板的夹具。
- 不提交、合并、推送、发布；不改 PersonalAgent 源码、实例配置或私自改 task-ledger。
- 输出使用任务专属目录及唯一文件名；不执行会写历史结果的旧入口。历史失败和事故凭证保留。

## 审查重点

1. 第二门预加载后不提前充能或错误解锁；第一门开启不重置、删除或串用第二门进度。
2. 开第一门时落后角色仍在门前：选门变化不能夹人、强推或制造绳路死锁。
3. 正反角色分配及门间换位：不能依赖模拟轴、瞬移或放宽段尾容差。
4. 暂停发生在开门边界，失败重试发生在第二门等待区：计时冻结、旧输入清除、独立重置及同步状态一致。
5. 重复安装、预加载回收及 world_origin 重定位：ID、坐标、锁存和计分状态不串实例，显示槽复用不重播旧提示。

## 实施步骤

### 1. 双门数据和安装反例

文件：新增 `tests/cooperative_relay.gd`；修改 `scripts/road_templates.gd` 的 make_block、extra_hazards，`scripts/road_run.gd` 的 install_block。

- [ ] 先写并执行缺失路线反例；预期新模板不存在/门数不足，测试非零退出。保持旧单门断言。
- [ ] 最小模板构造采用以下接口；字段 gates 仅用于新路线，gate 保持现有格式：

```gdscript
var charge := ChargeGate.make_tutorial()
ChargeGate.relocate(charge, 60.0)
var plates := SyncPlates.make_tutorial()
ChargeGate.relocate(plates, 190.0)
return {"route": "charge_sync_relay", "lane": 0.0,
    "gates": [charge, plates], "hazards": [], "rewards": []}
```

- [ ] install_block 先把原 gate 或新 gates 规范为列表，再逐门深复制、重定位和入队。原单门 ID 仍为 prefix+":gate"；新门分别为 prefix+":gate:0"、prefix+":gate:1"。按稳定 ID 逐门幂等，不因已有一门跳过另一门。
- [ ] extra_hazards 对 `charge_sync_relay` 返回空数组；decorate 维持空 hazards，不附加封路物。金币链仍由生产安全足点生成，不改变物理。
- [ ] 验证初态两个关闭实例、独立字典、首门选择、重复安装无新增门；同模板安装两个 prefix 后共四个不同 ID。

### 2. 固定步接力与安全转换

文件：`scripts/road_templates.gd` 的 route_input、existing_route_input、validate_block；`scripts/road_run.gd` 只在生产反例显示必要时修正选门或碰撞。

- [ ] 使用现有当前门分派：charge 走 ChargeGate.route_input，sync_plates 走 SyncPlates.route_input；最后使用安全段归队控制。不增加新的玩家自动控制。
- [ ] 验证器的超时预算随门数量增长；如果现有每门 240 步不足，记录两门实际调整时间再修改预算。超时不能记作成功或无限循环。
- [ ] 三难度各测正常/角色交换，并在第二门前主动等待、后退和重新站位；角色位置仅由 run.step 更新。
- [ ] 反例覆盖首门不足 0.8 秒、张紧/绳路高度不符、单人触碰；次门不足 42 固定步、同板、腾空、离板；均不解锁。充能门需计满 96 步，踏板需 42 步，按生产浮点容差核对临界帧。
- [ ] 逐帧保存原始双人输入、门 ID/open/charge/occupied、双方坐标高度、绳路长度和哈希。重复落盘复放所得状态指纹完全一致；闭门尝试跳跃仍受连续碰撞约束。

测试断言骨架（run 和 block 均使用既有生产类）：

```gdscript
check("接力两门", block.get("gates", []).size() == 2)
run.install_block(block, 0.0, "relay")
check("两门独立关闭", run.charge_gates.size() == 2
    and not run.charge_gates[0].open and not run.charge_gates[1].open)
check("先选充能门", run.charge_gate.id == "relay:gate:0")
# 下面每帧只通过生产 step 改变位置，记录并复放合法输入。
check("输入合法", Templates.keyboard_legal(axes[0]) and Templates.keyboard_legal(axes[1]))
check("绳长有效", run.rope.required <= run.LINK_LIMIT + 0.01)
```

### 3. 生产抽签和反馈

文件：`scripts/road_templates.gd` 的 candidate_block；`scripts/road_demo.gd` 的 sync_charge_gate；新增 `tests/cooperative_relay_view.gd`；修改 `tests/random_scene.gd`、README。

- [ ] 三关随机袋各加入一个接力路线；保留前八段至少一个 sync_cargo、相邻同类型不重复的现有契约。接力段安排在每袋前十二消费位置内，避免有限关卡到终点仍没出现。调换位置时不能破坏旧踏板保证，增加 100 种子重洗边界断言。
- [ ] 第一关仍先充能教学、踏板教学，再随机池；第二、三关不重播教学。接力从完整入口状态生成当前源码证书，实际安装失败不能假记已抽到。
- [ ] 门字典只增加可被哈希/快照保存的显示元数据 `relay_index=0/1`、`relay_count=2`；当前提示显示“接力 1/2 充能”“接力 2/2 踏板”。进度、占用、门可见性、音效仍按实例 ID 更新。
- [ ] headless 视图测试只验节点位置、显隐、文字和重复开启提示；不称为画面或手感通过。

### 4. 状态恢复与联机

文件：`tests/cooperative_relay.gd` 生命周期组；`tests/online_lockstep.gd`。

- [ ] 四门预加载、逐门开锁、回收、相同 ID 安装、换 prefix 重用；事件每门仅一次，金币每稳定 ID 仅计一次。
- [ ] capture_state/clone_state 后修改副本的第二门进度、occupied，原实例不变；clone 当前门必须别名绑定自己的队列成员。world_origin 重定位同时平移两门，保留世界坐标、ID和计时。重定位夹具不冒充无瞬移路线。
- [ ] 第一门充能中、第二门站板中、首门已开次门未开三种状态分别暂停；冻结全部状态。生产失败后重试恢复两门初态，清空旧点按和本关奖励；关卡切换不残留门。
- [ ] 本机 UDP 两客户端完成接力；比较全部共同帧 sync_hash 及两门关键字段。覆盖角色交换、等待回撤、暂停恢复、第二门前失败重试和安全退出。日志保存共同帧数、差异数、两门事件次数；零差异才通过。

### 5. 验证闭环与收尾

- [ ] 运行三难度 × 三关 × 三固定种子 4242/812208/20261014 × 两种角色分配，共 54 组生产生成与落盘复放。无强制改抽签袋、无角色坐标赋值、原始轴全部合法；两门真实出现、按序开启并安全退出，奖励全可达且护盾消耗不增加。
- [ ] 复用受影响的 road_charge_gate、road_sync_plates、gate_combinations、sync_plates_combinations、random_scene 入口；不重复无影响的历史全量，也不把旧失败删掉。
- [ ] 运行所有测试前先核查其输出路径；新测试使用 `COOPERATIVE_RELAY_EVIDENCE` 指向本任务目录，禁止存在即覆盖。命令退出码、超时、stderr 警告和关键行全部单列。
- [ ] 配置决策者核对当前源码绑定、54 组凭证、选门/碰撞代码、一次独立生产复放和生命周期验证；选择必要检查，记录结论。Controller tests=[]，只调度和收集，不代做验收。
- [ ] 更新 `docs/COOPERATIVE_RELAY_T07_REPORT.md`，含实际改动、启动方法、分支、未提交状态、失败与待试玩、清理报告。完成后关闭自己启动的测试与 UDP 进程，释放自己的 Writer；管理 LSP保留。
- [ ] 证据保留最终日志、原始合法输入及必要失败、源码哈希和恢复索引；删除任务自身重复日志、试错副本及不再需要的隔离工程。拒绝经 junction/symlink 递归清理；不清共享 .godot 或归属不明文件。

执行命令模板（实施时填写实际唯一任务路径；当前均未运行）：

```powershell
$env:COOPERATIVE_RELAY_EVIDENCE = 'D:/ConjoinedTwins-task-temp/1899707b-t07-relay/routes'
rtk proxy D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:/ConjoinedTwins --script res://tests/cooperative_relay.gd
rtk proxy D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:/ConjoinedTwins --script res://tests/cooperative_relay_view.gd
rtk proxy D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:/ConjoinedTwins --script res://tests/online_lockstep.gd
rtk git diff --check
```

## 滚动队列：不能把普通 pass 当作长期结束

本节是待交 Controller 的非空后续任务定义，不是已落账或已调度的事实。本轮工具列表未提供 PersonalAgent Controller 任务追加/计划更新接口；没有调用无关云端自动化，也没有私写账本。

### t08-cooperative-relay-recovery

dependsOn：t07-cooperative-relay-and-continue。

指令：接力段通过后，先处理 t07 新发现的阻碍游玩缺陷。若没有阻碍，实现第二門等待区的失败原因与恢复提示：区分站位不足、腾空、绳路高度不符及正常等待，避免显示“受阻即将失败”误导安全等待玩家。复用门状态与现有 HUD，不改机关开锁规则；覆盖两种角色分配及联机同步，完成后返回下一任务。

验收条件：

- 安全等待、未站稳、腾空与有效充能四种状态的提示对应真实生产判定；正常等待不出现失败倒计时，无未满足条件却显示已开。
- 三难度、双方交换完成接力；等待/回撤/暂停恢复/失败重试状态正确，原合法路线和两门锁存保持。
- 两客户端共同帧物理哈希不变且提示来源一致；headless 节点文字验证与真实视觉试玩分开。
- 当前源码凭证、配置决策者结论及实际清理报告完整；保留原 Run，不提交或合并。

### t09-industrial-relay-theme

dependsOn：t08-cooperative-relay-recovery。

指令：在现有程序资产内制作工业供能主题接力段，用供电指示、门间地面导向和出口照明强化两人共同充能与站板次序。只使用小体积项目内资产，不新增敌人或改变已验证几何；三难度随机池保留合法出口和独立状态。若出现新游玩阻碍，先以明确缺陷修复任务取代本项再进入主题扩展。

验收条件：

- 相同种子生成主题元数据可复现，门 ID/碰撞/计时/奖励与既有接力契约一致，生产路线复放通过。
- 两门反馈独立，预加载与节点槽重用不会串色、串提示、重复音效；暂停和重试恢复主题状态。
- headless 节点绑定、当前源码证据与清理审计通过；可见画面和用户试玩仍如实待验。
- 验收时再返回至少一个有指令、dependsOn 和具体验收条件的后续真实增量，不返回空建议清单。

### Controller 交接和恢复要求

在 t07 最后一次决策验收返回中携带上述后续任务。由原 Controller 支持的响应协议或真实追加接口保存，随后只读核对 plan/账本包含任务 ID、依赖、指令、验收条件及下一 taskIndex，再核对实际进入下一任务。若保存或调度未发生，状态是“功能验收通过、持续调度未完成”，不能声称整项 pass 或长期目标 complete。

中断保存原 Run ID、当前 t07 阶段、源码绑定、Writer 归属和后续任务定义；恢复入口为原检查点、已有 t06 决策凭证及本计划。只有用户停止或实际外部限制才停止推进；本次结束仅交回规划结果，不将长期目标标记完成。

## 本次规划核查与清理报告

本轮没有执行玩法测试或独立验收。仅新建本计划与项目外规划凭证；既有文件和账本由 before/after 哈希核对。恢复检查点使用紧凑 JSON 的规范化 SHA256，与交接标识相符；原始文件字节哈希另行登记。

凭证目录：`D:/ConjoinedTwins-task-temp/1899707b-t07-planning/`。保留 inspect.py、baseline.json、final.json 及最终核查日志用于复核；无重复下载、隔离工程或后台写入进程。本次没有启动 Godot、UDP 或编辑器，管理方 LSP 保留。无须删除源码或前轮恢复材料，无未能清理项。
