# t02 障碍与动作反馈：决策者审查

日期：2026-10-12。任务：`t02-obstacles-and-action-feedback`。结论：返工后复验通过。下面保留首次返工原因，最新结论及证据见文末。

## 已验证部分

核对生产危险定义、固定步碰撞、危险显示及动作反馈代码。六类危险与飞行物三种高度均已接入当前 450 米路线；双人规则及固定镜头保留，无低姿态动作或拾取逻辑。检查 `build-tools/obstacles-baseline.zip`，5 个条目，CRC 检查无错误。此次不声明全量项目变更已经核对。

独立复跑执行者检查，保留原断言并将证据输出到不同文件：

- `tests/decision_duo_t02_review.gd`：40/40 通过，退出码 0；结果 `tests/decision-duo-t02-result.json`，日志 `tests/decision-duo-t02-headless.log`。
- `tests/decision_obstacles_t02_review.gd`：50/50 通过，退出码 0；结果 `tests/decision-obstacles-t02-result.json`，日志 `tests/decision-obstacles-t02-headless.log`。

以上命令均使用 Godot `4.7.1.stable.official.a13da4feb`、`--headless --path D:/ConjoinedTwins --script res://tests/<脚本>`，没有桌面输入或 GUI 操作。首次启动复跑时副本写入进程尚未完成，得到脚本不存在错误；等待该进程正常退出后重新运行，以上为实际完成的结果。

实际打开查看 `docs/screenshots/t02-spikes-active.png`、`t02-fly_body.png`、`t02-scanner.png`。地刺尖锥、身体高度飞行物、扫描束安全状态与文字可辨，宽道路、双方角色、地面阴影与连线仍可读。截图审查不代表实体键盘、实时动画或双人手感验收。

## 首次返工问题：动态刺高导致提前致命（已修复）

`scripts/road_run.gd` 的 `fixed_step()` 取子步首尾危险高度的最大值作为整个子步的静态上界，再调用 `swept_body_hits()`。后者虽然让角色平面与高度共用时间参数，却没有同步危险高度的变化，因此在地刺伸出时会把未来的高度提前应用于接触。

独立复现脚本：`tests/decision_dynamic_hazard_probe.gd`。实际运行命令：

```powershell
rtk proxy "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path D:/ConjoinedTwins --script res://tests/decision_dynamic_hazard_probe.gd --log-file D:/ConjoinedTwins/tests/decision-dynamic-hazard-probe.log
```

退出码 1，结果为 `tests/decision-dynamic-hazard-probe.json`。该明确夹具保留生产跳跃初速 110、重力 240、自动推进速度 120、活动刺最大高度 16、4 秒周期及 0.25 秒伸出时间；仅将一组活动刺移到 `Rect2(-55, 149.333333333333, 26, 8)`，玩家一在 1.05 秒按下跳跃。双方仍通过正常输入及生产固定步更新，没有修改角色位置、关闭约束或直接设置高度。

按半径 12 扩张后的平面接触时间为约 1.144444 至 1.411111 秒。角色跳跃高度为 `110*(t-1.05)-120*(t-1.05)^2`；伸出段刺高为 `64*(t-1)`，完整伸出后为 16。整个平面接触区间角色底部都高于真实刺顶，最小净空约 0.074074 地面单位，故本夹具应合法通过。实际却在物理时间约 1.147224 秒共同失败：角色高度 9.560185，真实刺高 9.422347，净空仍为正值 0.137838。

这不是实体键盘或可见 GUI 缺证据，而是实际生产碰撞的独立可复现错误，阻止本任务通过。

## 原返工要求

按同一时间参数处理角色运动、动态危险运动及底顶高度；对激活、失活、伸出、完整伸出和回落边界按需分段处理，不能以全子步高度包络替代实际时间判定。保留上述复现及预期合法通过的断言，修复后该脚本应退出 0；补充双方伸出/回落接触边界检查，并复跑既有双人回归、高速扫掠及动态周期检查。不要修改可信断言、扩大高度容差或改变本夹具输入来掩盖误判。

本次未修改生产实现。Controller 独立测试未运行，配置为 `tests=[]`；执行者记录的可见 GUI `deferred_by_work_mode` 和真人试玩边界继续保留。没有本轮 Mac 导出、提交、合并、推送或公开发布；所有审查进程均已退出。

## 返工后独立复验

决策者核对 `build-tools/dynamic-hazard-baseline.zip`：3 个条目，CRC 检查无错误；备份包含返工前生产规则、原决策者探针及本报告。与备份逐字节比较，只有 `scripts/road_run.gd` 改变，原探针保持不变。原探针 SHA256 为 `6393fd0962379c52ae609a3f983358f1369d3a777abf7c82bcf074a918234e2d`。

生产碰撞现调用 `timed_hazard_hits()`，在危险激活、失活、伸缩斜率及飞行轨迹边界切段，各段把双方地面位置、角色底部高度、危险矩形及底顶高度转为同一时间参数的线性约束求交。审查未发现扩大高度容差或改变跳跃参数以掩盖原问题。

使用同一 Godot 引擎及 headless 入口，决策者实际执行以下四项，退出码均为 0：

- 原 `tests/decision_dynamic_hazard_probe.gd`：保持原输入与预期，角色合法通过危险，运行到距离 240，状态 `running`、失败原因为空。结果和日志沿用该探针文件名。结果中最终高度为 0、刺高为 16，此时角色已离开该危险矩形，最终 `clearance=-16` 不是接触期间的净空。
- `tests/decision_dynamic_hazard_t02_review.gd`：独立复跑新增 16/16 动态边界检查，结果 `tests/decision-dynamic-hazard-t02-result.json`，日志 `tests/decision-dynamic-hazard-t02.log`。原测试副本仅改输出路径，未改变断言；覆盖双方合法净空、真实命中、伸出/回落及跨激活/失活边界。
- `tests/decision_duo_t02_review.gd`：40/40 双人生产回归通过，包含正常输入完成 450 米路线。结果和日志见上文对应路径。
- `tests/decision_obstacles_t02_review.gd`：50/50 障碍专项通过，保留双方高速扫掠、周期、起跳/落地、视觉同步和重试检查。结果和日志见上文对应路径。

共 106 项检查及原误判探针通过。返工只调整碰撞规则，执行者未修改视觉模型或重新截图；本任务视觉结论沿用首次审查实际查看的三张运行截图，不把它们称作返工后的新渲染。本次决策者未再修改生产实现。

据此 t02 通过，可继续后续无限道路与难度任务。Controller 独立测试仍未运行；真实键盘、实时动画手感、双人协作及 Mac 实机仍待用户验收。本次 headless 进程均正常退出，没有后台写入进程。
