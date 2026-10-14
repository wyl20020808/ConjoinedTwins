## 决策者补充验收与持续推进（2026-10-14）

本节由配置决策者写入，记录自动交回后的自主判断。t06 的生产玩法、合法路线、状态生命周期、联机与受影响回归验收通过；历史结果恢复事故仍然未解决。本节更新此前 pending 的验收状态，以下执行者报告和原始保护审计保留原结论，不把它们改写为事故已恢复或保护审计通过。

当前源码与已核实的生产绑定一致。沿用 27 组、44,744 帧落盘合法输入复放、UDP 2708 个共同帧零差异，以及决策者独立复验困难第三关和生命周期专项 33/33、退出 0。本次重新核对返工日志与证据哈希、全部断言主体不变、拒写保护及清理路径，没有重复运行未变玩法矩阵。输出隔离通过，旧速度规则 10 项失败仍保留。补充验收凭证：`D:/ConjoinedTwins-task-temp/1899707b-t06-decision-continuation/acceptance.json`。

历史事故单列为未恢复事项：`build-tools/obstacle-expansion-6377e8b8/speed-guidance/result.json` 的原 SHA256 为 `3cb9e601e241f3c3f2c4daf68615906a0f4ca82e664e7aef3d58411a3da09d5d`，当前为 `68b3eff3a2b09ebd396b67f51c1607dd563e0343d6021faa85415d1e172c547a`。当前文件是误写结果，不能作为原历史验收凭证；不得把重建结果、其他历史结果或新的基线冒充原件。保留事故、恢复尝试及原审计，`original_restored=false`、`workspace_protection_passed=false` 不变。获得新的可靠备份后再核对恢复，不重复没有新材料的恢复实验。

此前将历史恢复缺口扩大为全部开发阻塞，范围过大。既有长期目标明确允许外部条件受阻时保留证据并推进不依赖它的工作；当前 t06 凭证和后续 t07 均不依赖被覆盖的旧速度结果。因此完成当前功能验收，交 Controller 继续既有 t07，而不是结束长期目标。这是决策者对开发顺序和验收范围的判断，不是用户同意遗失证据，也不是豁免历史证据保护要求。Controller `tests=[]`；GUI 仍为 `deferred_by_work_mode`；真实设备输入和用户试玩未运行。

清理报告：本次未删除源码、历史结果或审计记录；保留本次验收脚本、最终凭证和修改前报告副本，用于复核。本次未启动测试、UDP 或后台服务；本次 Writer 在写入后释放。执行者登记删除路径重新核对均不存在，受管理 headless LSP 保留。无未能清理的本次中间产物或进程。分支仍为 `feature/charge-gate`，未提交、合并或推送。

---

# 同步踏板组合 t06 实施报告

## 输出隔离返工进度

按本轮决策者反馈，仅修改 `tests/speed_guidance_rules.gd` 的结果输出，不修改玩法源码或既有断言。现在必须通过 `SPEED_GUIDANCE_EVIDENCE` 指定项目外任务目录中尚不存在的绝对 `.json` 文件路径；缺失、项目内路径、非 JSON 后缀或已存在文件均在运行检查前退出 2。输出路径采用规范化字符串检查，不宣称已经实现对全部 Windows 路径别名的物理隔离；拒绝覆盖已存在文件额外保护了既有结果。

返工证据位于 `D:/ConjoinedTwins-task-temp/1899707b-t06-sync-combinations/output-repair/`。`isolation.json` 核对整个检查主体与改前逐行相同，并保存拒写和任务外输出的实际进程退出码、日志及历史结果哈希。合法路径仍执行 487 项，旧速度规则的 10 项失败保留，退出 1；不能把输出隔离通过当作旧玩法断言全部通过。

决策者已支持原 27 组、44,744 帧与联机结果，独立复验困难第三关和生命周期专项为 33/33、退出 0。本轮生产源码绑定未变，复用既有凭证，没有重做 t05 或完整矩阵。配置决策者对本轮返工尚未验收。

恢复链核对：`speed-guidance/baseline.zip` 含追加前 353 文件，不含目标结果；`source.diff` 仅源码和文档差异。旧 `change-manifest.json` 记录的结果哈希为 `43a1e669...`，与旧 `decision-review/result.json` 一致，但与本轮原哈希 `3cb9e601...` 不同，故未用于替换。隔离还原差异时源码字节哈希亦未匹配旧 manifest，实验立即拒绝，没有运行该不完整恢复工程或写回历史文件。**本轮原件仍未恢复，保护审计仍失败，t06 完整验收保持 pending。** 最终核对及清理见返工目录 `repair-closeout.json`，前轮审计和收尾文件保留，不覆盖历史结论。

返工验证命令：`G res://tests/speed_guidance_rules.gd`。未提供环境变量以及指定历史结果路径、非 JSON 文件或已存在文件时，实际退出 2，日志为 `missing.log`、`historical.log`、`non-json.log`、`existing.log`；指定任务目录的新 JSON 文件时退出 1，`isolated.log` 关键行为 `SPEED_GUIDANCE checks=487 failures=10`。每种情况的展开命令、环境变量和哈希见对应 `*.receipt.json`。Python 总体验证 `verify_isolation.py` 退出 0，仅表示隔离契约和保留断言核对通过。

## 当前结论与交接

本轮已实际实现生产随机踏板组合，功能自测通过。**本轮不能宣称完整验收通过：执行旧速度检查时误写了一份既有历史结果，原内容尚未恢复。** 交原 Run 的配置决策者核对本报告、代码、凭证和该事故；不将独立代码审查、自测或 Controller 调度当作决策者验收。决策者通过后继续既有 t07，长期目标保持进行；当前不提前宣布 t06 完成。

Run：`1899707b-57d1-433f-a67c-ce96f314d04e`。沿用 `feature/charge-gate`，起点 HEAD 为 `4743fa50f3110b1c9ed67ce423c9572cc131db6e`，没有提交、合并或推送。t05 已验收，本轮仅做受影响回归，没有重建历史任务或修改 Controller 账本。

证据根目录：`D:/ConjoinedTwins-task-temp/1899707b-t06-sync-combinations/`。恢复材料为 `start.json`、`before/`；最终入口为 `final-evidence.json`、`final-audit.json`、`cleanup.json`、`closeout.json`。Writer 使用原子独占创建 `.git/t06-sync-combinations-writer.json`，归属本任务，收尾仅释放自己的锁。

## 实际实现

- `scripts/road_templates.gd`：三关随机袋加入 `sync_cargo`；洗牌后确保每袋的前八个消费位置内出现踏板组合，位置仍由本地种子 RNG 确定。先处理避免连续同类，再安排窗口；上一段为踏板时不将其换到首消费槽。其余种类通过交换保留，不复制或删去旧种类。
- 新组合复用 `road_sync_plates.gd` 的占板、0.35 秒同步与锁存规则，复用稳定实例 ID、门队列、捕获/克隆、真实绳路、生产碰撞和展示。第一关仍是充能教学、踏板教学、随机段；后续关卡不重复教学。
- 相对段起点，踏板中心在纵坐标 120，关闭门在 210，货箱在 430–495。双方先分站，再共同换到左右随机选定的一侧；570 后回到中央。门前等待和回撤没有加入危险；门后的换侧空间由实际路线复证。两枚基础币布局经生产生成器替换为沿安全路线生成的金币链；验证按实际奖励数量核对全部稳定 ID。
- `scripts/dynamic_threats.gd`、`scripts/road_run.gd`：本轮真实随机前序暴露出旧迎面物按当前纵向输入触发预警，下一步换键可骤减 TTC。预警现在考虑合法最大前速，并保留当帧实际相对速度与 TTC；未降低既有预警、绳长或碰撞验收阈值。
- 新增 `tests/sync_plates_combinations.gd`、`tests/sync_plates_combinations_view.gd`，扩展 `tests/online_lockstep.gd`。README 已按生产金币链行为更新。

## 当轮验证

27 组使用三难度、三关、固定种子 4242 / 812208 / 20261014。从生产出生状态和正常随机池运行，未强行指定矩阵的抽签袋、未瞬移角色、未关闭碰撞或用护盾掩盖失败。落盘后从文件读取每帧原始输入，在新 Run 复放，逐帧状态指纹一致，共 44,744 帧。输入轴仅 -1/0/1；双方完成开门、绕箱、全部实际奖励领取并安全退出，护盾使用不增加。源码绑定为 `a91a2d0df59b3ca1a7d9d1728604c1cc3f58b7217c08c3f8af076ab3c916adab`。

专项覆盖：100 个种子的重洗袋边界；左右绕行及交换板位；预加载多门独立状态与克隆别名隔离；回收、重用和重复 ID；奖励不重复；暂停、重试和关卡切换；坐标重定位；关闭门等待、合法回撤、身体及绳路门碰撞，再合作退出。重定位专项手动构造远坐标状态，单独标注为生命周期夹具，不作为合法游玩路线证据。

UDP 采用中转服务器与两个真实生产场景客户端，经本机 UDP、正常时间步和合法轴值运行。为聚焦新组合，联机专项将首个候选袋设为 `sync_cargo`，其余生成、碰撞、输入提交与网络帧仍走生产接口；这项定向设置与上述正常随机矩阵分开。最终 2708 个共同帧零差异，含占板、计时、开门、双方绕箱、实际生成的 8 枚金币全部领取及退出；零自动重试、零护盾消耗。暂停、显式重试、输入清除、断线和线程快慢差异检查仍保留。

以下 `G` 是准确的公共命令前缀：

`D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path D:/ConjoinedTwins --script`

日志均位于上述证据根目录；每条 `*.receipt.json` 包含展开的命令、环境、退出码、日志 SHA256、脚本 SHA256 和进程退出状态。环境输出目录为 `routes/`、`tutorial/`、`charge/`、`online.jsonl`，分别对应 `SYNC_COMBINATIONS_EVIDENCE`、`SYNC_PLATES_EVIDENCE`、`GATE_COMBINATIONS_EVIDENCE`、`ONLINE_GATES_EVIDENCE`。

| 检查命令 | 退出码 | 日志 | 关键结果 |
| --- | ---: | --- | --- |
| `G res://tests/sync_plates_combinations.gd` | 0 | `combinations-verified.log` | `SYNC_COMBINATIONS checks=59 failures=0`，27 条 `replay=true legal=true opened=true claimed=true` |
| `G res://tests/online_lockstep.gd` | 0 | `online-rewards-final.log` | `RESULT 21/21 passed`；`common_frames=2708 equal=true`；`exited=true rewards=8 collision_free=true retries=0` |
| `G res://tests/road_sync_plates.gd` | 0 | `plates-final.log` | `SYNC_PLATES checks=50 failures=0`，18 条教学保存复放 |
| `G res://tests/road_charge_gate.gd` | 0 | `charge-final.log` | `CHARGE_GATE checks=39 failures=0 legal_axes=true` |
| `G res://tests/gate_combinations.gd` | 0 | `old-combinations-final.log` | `GATE_COMBINATIONS checks=97 failures=0`，受影响的 27 组充能组合 |
| `G res://tests/random_scene.gd` | 0 | `random-scene.log` | `SCENE failed=0`，生产场景第一关运行 |
| `G res://tests/baseline_controls.gd` | 0 | `controls.log` | `BASELINE_CONTROLS failures=0` |
| `G res://tests/baseline_landing.gd` | 0 | `landing.log` | `landed=5 hooked=6 geometry_errors=0 passed=true` |
| `G res://tests/baseline_rope_view.gd` | 0 | `rope-view.log` | `BASELINE_ROPE_VIEW failures=0` |
| `G res://tests/gate_combinations_view.gd` | 0 | `combination-view.log` | `GATE_VIEW failures=0` |
| `G res://tests/sync_plates_combinations_view.gd` | 0 | `sync-view.log` | `SYNC_COMBINATIONS_VIEW failures=0`；2 个 ObjectDB 泄漏警告 |

控制夹具有重复解析输入事件的既有警告；新踏板显示专项有两个 ObjectDB 实例退出泄漏警告，未伪报为无警告。显示专项手动改变状态，只验节点位置、显隐、身份回收，不证明可见画面与操作手感。

## 失败、事故及未完成事项

1. 初始随机踏板复用了教学纵坐标，开门后换侧距离不足，预测消耗护盾；前移组合机关后修复。`collision-debug-fixed.log` 保留失败。没有删掉护盾、碰撞或绳长断言。
2. 旧迎面物换键后的预警不足见 `warning-debug.log`；`warning-behavior-red.log` 保存行为反例。首次新接口反例有参数个数错误，见 `warning-red.log`，不把该解析失败算作行为验证。
3. 首次正常随机矩阵在简单/1/20261014 到结算仍未抽到踏板组合。见 `combinations-final.log`，该长跑主动中断，Godot 退出码 15，不能当作通过或超时。新增窗口约束后重新完成全矩阵。更早 `routes-first`、`routes-debug` 同样主动中断；它们不作为最终源码绑定的复放证据。
4. UDP 扩展退出断言后先发现循环过早结束，后发现四倍时间下控制回显过冲，见 `online-complete.log`、`online-exit-verified.log`、`online-retry-debug.log`。保持安全与零重试断言，改为正常时间后通过；最终再次加强完整奖励链及双方退出断言，并复验通过。没有发生最终验证超时。
5. 旧 `tests/speed_guidance_rules.gd` 返回 1，仍硬编码 140/160/180 推进和 -360 火箭，当前生产为 250/295/330 和 -860。其十条失败在隔离的变更前脚本、HEAD 脚本复跑中相同，见 `speed-rules.log`、`baseline-speed.log`、`head-speed.log`；没有修改旧断言来掩盖失败。
6. **事故：上述旧检查默认写入 `build-tools/obstacle-expansion-6377e8b8/speed-guidance/result.json`，覆盖了已存在的历史结果。** 原 SHA256：`3cb9e601e241f3c3f2c4daf68615906a0f4ca82e664e7aef3d58411a3da09d5d`。搜索限定项目候选文件、项目 ZIP 和任务证据，没有匹配副本；隔离重建值亦不匹配，故没有用重建内容冒充原文件。当前值及两份重建结果集中留证，见 `incident-current-result.json`、`baseline-recovery.json`、`head-recovery.json`。该项未恢复，`workspace_protection_passed=false`，不可宣称全部无关成果完整保留。

独立 native 审查已指出并推动修复护盾断言、随机袋边界和 UDP 奖励数量遗漏；审查记录由实际子代理消息汇总到证据目录，未伪称配置中的 OpenCode 执行者或最终决策者运行。配置决策者验收 pending；Controller `tests=[]`；GUI `deferred_by_work_mode`；真实设备输入、用户试玩、Mac 实机均未运行。

## 清理报告

已删除本轮创建的隔离重建工程（398 个文件，仅 311,955 字节为独占内容，其余为本轮创建的文件硬链接，删除链接不删除原资源）及 18 份重复成功日志/receipt，共释放 343,660 字节独占内容；没有通过 junction/symlink 递归删除。失败、主动中断、恢复材料、最终路线和联机痕迹保留，原因是审计与复核所需。Serena 自动更新的两个符号缓存保留，不回写旧缓存，不将其当作源码改动。历史误写项保留当前证据，未恢复是完整性事故，不是可删除的垃圾。

测试、UDP 和重建进程均已退出。受管理 LSP 的 PID 4208、38928 保留；没有另起或终止编辑器。Writer 在最终收尾释放，实际核对见 `closeout.json`。无未能清理的本轮临时进程或目录；历史结果恢复仍未解决。源码、正式资产、其他任务及前轮证据没有删除。
