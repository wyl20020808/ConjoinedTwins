# 充能与踏板接力 · t07 实施报告

原 Run：`1899707b-57d1-433f-a67c-ce96f314d04e`。分支：`feature/charge-gate`。未提交、合并、推送或发布；原有脏工作保留。

**当前结论：实施、自测及独立代码/headless复核已完成，外部配置决策者验收和 Controller 后续任务持久化仍未完成。长期目标没有标记完成。** Controller 独立测试为 `tests=[]`，用户试玩未运行；按用户明确要求不碰桌面，GUI 为 `deferred_by_work_mode`。策略文件实读为 idle，不扩大桌面授权。

## 实际改动

- `scripts/road_templates.gd` 新增 `charge_sync_relay`：840 单位独立段，充能站位在 120、门在 210；踏板站位在 480、门在 570。前十二个随机段内出现，保留原踏板组合前八段契约和换袋不连抽相同类型。该段不散布额外危险，门间留有调整区，第二门后留有退出区。
- 模板退出区提供三枚金币；实际随机生成继续复用生产验证足点建链，最终奖励数量由生产路线决定。矩阵逐个核对该实例完整奖励领取，不能把模板金币数量当作生成后的实际数量。
- `scripts/road_run.gd` 复用原门队列、碰撞、选门及恢复，安装 `prefix:gate:0/1`；每门独立计时、占用、开锁和事件。旧单门 `prefix:gate` 契约保留。安装同时检查历史 installed 事件，回收后同 ID 不会再生成关闭门；重试清空实例历史，重新安装仍可用。
- `scripts/road_demo.gd` 标注“接力 1/2 · 充能”“接力 2/2 · 踏板”，原门型、进度、开门和回收反馈复用。
- 新增 `tests/cooperative_relay.gd`、`cooperative_relay_view.gd`、`cooperative_relay_online.gd`。UDP 专项继承原联机测试，保留其断言，通过组合类型钩子选择接力段；补首门锁存、次门独立及次门计时中暂停/恢复。原 UDP 暂停夹具增加“第三段已加载”条件，修复后台生成尚未完成就暂停的竞态，未降低加载或共同帧断言。
- README 追加真实行为及本报告入口。

## 当前验证

证据根目录：`D:/ConjoinedTwins-task-temp/1899707b-t07-relay/`。生产源码聚合绑定：`34ce2e5c173458aee2a4c9800a4d99efc223b9d23da3b8a7990c6e45a75341ca`。

| 检查 | 实际结果 | 日志 |
| --- | --- | --- |
| 三难度 × 三关 × 三种子 × 正反分配自然生产生成及落盘复放 | 54/54，`RELAY checks=92 failures=0` | `accepted-matrix.log` |
| 最新生命周期、失败入口恢复及换关夹具 | `RELAY checks=44 failures=0` | `lifecycle-complete.log` |
| 原充能教学/碰撞/路线回归 | 39/39，合法轴 | `charge-regression.log` |
| 原踏板教学矩阵及恢复回归 | 50/50 | `plates-final.log` |
| 生产随机整关场景、绳网格、奖励和声音 | `SCENE failed=0` | `random-scene.log` |
| 原真实 UDP 回归 | 21/21 | `old-udp-race-fixed.log` |
| 接力真实 UDP，次门计时中暂停恢复 | 23/23 | `udp-complete.log` |
| 双门显示次序、位置、开锁及身份回收 | 4/4，无脚本错误或退出资源泄漏警告 | `view-clean.log` |
| 独立困难/第3关/20261014/交换角色 | 45/45，2185 固定步，最大绳长 131.76271 | `review/independent-hard-swap/run.log` |
| 当前证据/受保护文件审计 | 54/54 绑定当前源码、角色分配和逐帧字段完整；503 个受保护文件未变 | `audit.log`、`audit.json` |

矩阵使用生产 `1/120` 固定步、原始轴仅 `-1/0/1`，没有强制修改抽签袋或角色坐标。每份 JSONL 包含输入、状态指纹、门 ID/open/charge/occupied、双方坐标、origin、高度和绳长；重新从初态逐帧复放并比较指纹。记录位于 `accepted-matrix-routes/`，每组另有生成布局、事件及领取状态 certificate。审计另检查开门先后和正反角色的真实横坐标。

生命周期覆盖未协作时挡人、第一门和第二门充能中暂停冻结、离板跳跃不误开、合法输入回撤恢复、两实例四门独立开锁、奖励不重复、回收同 ID 幂等、新实例重用、深拷贝重新绑定和坐标重定位。失败恢复调用生产 `fail_threat`，换关使用独立结算状态及生产双人确认入口；这些是明确标注的恢复夹具，不是由碰撞输入自然触发的失败或全关结算证明。实际碰撞及自然结算分别由原教学和整关场景回归覆盖。

UDP 专项使用同进程服务器和两个真实生产场景客户端，经本机 UDP 比较共同帧全队列哈希，强制抽签仅用于专项选段，不能替代 54 组自然生产生成。UDP 当前覆盖默认角色分配、次门内暂停恢复、出口后重试和断线；交换角色及第二门前失败重试由本地固定步夹具覆盖，未声称这两项也在 UDP 运行过。

独立审查先发现同 ID 回收重装和旧凭证绑定问题，修复后再选困难交换角色独立复放，结论为未见新增阻断缺陷。此审查不是原 Controller 配置决策者的正式验收，也不是 GUI 或用户确认。

## 失败及修复证据

保留最初单门模板反例 `red.log`、退出奖励链反例 `rewards-red.log`、同 ID 回收重装反例 `recycled-id-red-valid.log`；最终检查保留对应断言。旧 UDP 首次 20/21 的失败在 `old-udp-final.log`：安全退出时仅两段已加载，提前暂停使后台安装无法继续，修正暂停时机后 21/21。

并行两项 UDP 误用同端口，造成监听失败；本任务冲突进程已结束，之后串行重跑。诊断日志 `accepted-udp.log`、`old-udp.log` 保留，不当作成功凭证。旧矩阵因实施过程中源码绑定改变失效，旧逐帧中间产物已删除，仅保留失败诊断 `final-matrix.log`；本报告只使用最终 accepted-matrix。

原踏板测试首次因证据目录不存在出现脚本错误，即使进程退出 0 也未采信；创建隔离目录后重新取得 50/50。显示测试首次退出时有 WAV 播放资源警告，专项夹具收尾显式停止播放器并等待音频释放，verbose 重跑无泄漏警告。未关闭生产音效或删减断言。

## 持续开发和恢复

后续可执行任务完整定义已保存在证据根 `followup-tasks.json`：`t08-cooperative-relay-recovery` 处理真实失败原因与安全等待恢复提示，随后 `t09-industrial-relay-theme` 制作工业供能主题。每项含 instruction、dependsOn 和具体验收条件。

**该文件仅为正式交接，Controller 尚未持久化或调度。** 只读调查原 Controller 的 CLI、源码和 dist：当前 executing 响应仅支持 native summary；规划响应 tasks/planUpdate 仅在 guidancePending 存在时应用并审计保存。原 Run 仍在 taskIndex=2，任务表只有 t05/t06/t07，guidancePending=null；本会话无可调用的 PersonalAgent 追加工具或正式 HTTP 入口。桌面 IPC 入口受“不碰桌面”限制，未调用，也未另起服务对象绕过原实例。

由原 Controller 接收本实施交接，交配置决策者验收，并通过正式引导/规划调用保存 t08/t09；随后只读核对任务 ID、依赖、验收条件和实际进入下一项。在保存/调度证据出现前，t07 的持续推进验收条件仍未完成，不标记整体 pass 或长期目标完成。无需新的用户目标或写入授权。

恢复入口：本报告、`followup-tasks.json`、原 Run 最新检查点、`baseline.json`、`before.zip`、`source.diff` 和最终凭证。不得重新规划或重做已验收 t05/t06；历史 speed-guidance 原件事故保持原状态，本轮未操作该历史证据。

## 清理报告

本轮清理记录在 `cleanup.json`、`cleanup.log`。删除过期两轮矩阵、首组试跑、重复 UDP trace、过程日志/receipt、临时停止脚本和已释放的 Writer；最终清理量以该记录为准。保留最终 54 组、独立复验、18 组踏板教学、两项最终 UDP trace、最终检查日志、必要反例/失败诊断以及恢复材料。可复用验证入口 `run.py`、`audit.py` 和进程审计脚本作为凭证保留；历史文件、用户文件及归属不明的项目缓存未删除。

任务 Godot 测试进程数为 0，Writer 已释放；6008 受管理 LSP 监听保留，没有启动或终止编辑器。无未能清理项。项目根/源码目录未散落临时日志、脚本或试错副本。独立清理复核另行记录，不用执行者清理声明代替验收。

## 验证凭证

每个最终 Godot 检查的确切 executable、参数、退出码、日志及耗时在同名 `.json` receipt；独立复验在 `review/independent-hard-swap/receipt.json`。可复用入口为：

```powershell
rtk proxy python -X utf8 D:/ConjoinedTwins-task-temp/1899707b-t07-relay/run.py test <label> res://tests/<script>.gd
```

最终已执行的 label/script：`accepted-matrix/cooperative_relay`、`lifecycle-complete/cooperative_relay`（环境 `RELAY_SKIP_MATRIX=1`）、`charge-regression/road_charge_gate`、`plates-final/road_sync_plates`、`random-scene/random_scene`、`old-udp-race-fixed/online_lockstep`、`udp-complete/cooperative_relay_online`、`view-clean/cooperative_relay_view`（追加 `--verbose`）。上述退出码均为 0。独立复验另设 `RELAY_CASE=困难-3-20261014-swap` 和自己的证据目录，退出码 0。

`rtk proxy python -X utf8 .../audit.py`：退出码 0，`AUDIT protected=503 changed=0 routes=54 valid=54`；`git diff --check`：退出码 0；进程审计及清理命令、退出码、实际关键行见最终 `evidence-index.json`。重复运行矩阵应更换 label/证据目录；测试拒绝覆盖既有 JSONL。
