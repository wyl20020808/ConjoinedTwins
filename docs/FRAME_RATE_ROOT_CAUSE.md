# 帧率根因复核与 Windows 高性能入口

本文使用整合前旧玩法副本，仅保留为历史本机诊断；当前完整玩法、统一入口和验证见 [最新玩法整合](LATEST_GAMEPLAY_INTEGRATION.md)。

本报告保留本机诊断历史。后续目标已纠正为降低游戏自身计算量，当前通用优化及对照结果见 [通用游戏计算优化](PORTABLE_GAME_PERFORMANCE.md)。下述 Windows 专用入口不作为通用优化成果，也不是使用通用改动的前提。

2026-10-18。沿用 `fix/dense-scene-performance` 与当前工作区，未重做已通过的碰撞、伤害及联机回归，未提交、合并、推送或发布。

## 结论及前次报告修正

本机为 i7-14700KF、RTX 4080 SUPER，Godot 日志确认使用该显卡。高帧率可以达到；先前只做到局部 CPU 优化，并用限帧、隐藏宿主与未充分控制的取样点给出了过窄的帧率结论。该结论不能当作电脑性能上限。

低帧率主要与以下路径共同有关：

1. 脚本模拟是 CPU 主线程负载。实际是 120 Hz 固定模拟，每固定步还执行三个运动子步，绳索再做十二轮约束、投影与实际路径连续碰撞；项目规模小不等于每帧计算量低。平均总 CPU 占用无法表示单个主线程是否已经耗尽预算。
2. 当前默认 Windows ANGLE / D3D11 兼容路径有显著的 CPU 提交成本。在性能核心与能效策略相同、同一密集路段、相同 144 FPS 上限、同为三秒以上采样的串行对照中，ANGLE 约 38.9 FPS，Vulkan 约 102.7 FPS；两者都保持 running，自动暂停次数为 0。原始参数和进程设置分别保存在 `angle-controlled-144` 与 `vulkan-controlled-144` 日志和 JSON 中。
3. 混合架构调度对这个重单线程负载影响很大。Windows CPU Set 查询报告逻辑核心 0–15 的 EfficiencyClass 为 1、16–27 为 0。在本次测试子进程中限定性能核心后，Vulkan 完整运行由低帧区间进入约 110–132 FPS；单独关闭该进程执行速度节流、但不限定核心的短测只有约 10 FPS。证据支持对性能核心敏感，不能据此断言用户前台游戏此前一直运行在某一个特定核心上。
4. 旧采样点在指定时间后会失去支撑，进入救援；旧夹具也受游戏自动失焦暂停影响。新夹具先设置模拟时间，再选择合法点，记录运行状态及自己恢复自动暂停的次数。用于下表的三次测试自动暂停次数均为 0，结束状态均为 running。

## 分层对照

1280×720，既有机关、动物、碰撞、伤害和绳索数量及参数均保留。

| 对照 | 结果 | 可得结论 |
| --- | --- | --- |
| ANGLE 只绘制静态密集场景 | 约 158 FPS | 原路径也有明显图形余量 |
| Vulkan 只绘制同类场景 | 约 1,151 FPS，GPU 中位约 0.20 毫秒 | GPU 绘制不是完整运行低帧的主因 |
| Vulkan 完整运行的早期拆分 | GPU 中位约 0.39 毫秒，主线程模拟占用高 | 后端切换本身不能解决全部脚本负载；该行末态为救援，不作为正常行走帧率 |
| 独立渲染线程＋ANGLE | GLAD 初始化失败，退出码 3221225477 | 不采用此方案；Godot 也明确提示该功能仍为实验性质 |

降低分辨率、关闭阴影，以及临时禁用绳索求解，仅作为诊断消融；这些设置没有写入生产玩法，也不计入高性能入口的交付帧率。ANGLE 的 GPU 测量返回 0，记录为不可用，没有解释成 GPU 耗时为零。

计时口径参考 [Godot RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)：viewport CPU 计时仅覆盖渲染相关工作，不能替代脚本模拟耗时。性能核心分级依据 [Windows CPU Set](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-system_cpu_set_information)；进程级执行速度策略使用 [PROCESS_POWER_THROTTLING_STATE](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-process_power_throttling_state)。

## 三章完整负载短测

Vulkan Mobile、性能核心、关闭仅此子进程的执行速度节流；解除帧率上限，每章至少三秒，在约 480 米密集路段静站，保留单人搭档逻辑及全部模拟与视图。含诊断探针开销，属于任务独占隐藏渲染，不能代替完整通关、前台键鼠或设备实测。

| 章节 | 平均 FPS | 帧耗时 p95 | 结束状态 |
| --- | ---: | ---: | --- |
| 穿林入村 | 69.3 | 17.28 毫秒 | running |
| 水车河道 | 121.7 | 14.96 毫秒 | running |
| 矿道归航 | 184.4 | 14.74 毫秒 | running |

第一章仍未达到 120 FPS，且其他章节的 p95 仍约 15 毫秒；不能宣称全部场景已经稳定 144 FPS。平均绘制帧率也不等同于移动画面已具备相同频率的平滑更新，物理仍是 60 Hz 外层、120 Hz 内部固定步，后续视图插值需要单独验收。

## 可用启动入口

双击任务工作区根目录的 `启动高帧率旅程.cmd`。调用 `build-tools/run_high_fps.py`，默认 144 FPS 上限，选择 Vulkan Mobile，并仅为它启动的 Godot 进程设置性能核心亲和性和进程执行速度策略。实际读取 CPU Set，不写死这台机器的核心数。退出即结束这些进程设置，不修改系统电源计划、驱动、注册表、其他进程或全局交互策略。原有跨平台渲染设置与入口保留。

启动参数可由用户手工设置，例如：

```powershell
python build-tools/run_high_fps.py --max-fps 180
```

真实启动链检查已从 `journey_boot.tscn` 完成资源准备并进入 `journey.tscn`，确认 Vulkan、Mobile、4080 SUPER、144 FPS 上限、外层物理 60 Hz，以及 start 状态。窗口始终是任务独占隐藏宿主，未操作用户桌面。可选后端的画面仍需用户实际试玩确认。

日志和进程设置回执：`build-tools/cache/high-fps/last-launch.log`、`last-launch.json`。深入诊断、截图、排除样本及源码绑定：`D:/ConjoinedTwins-task-temp/dense-performance-evidence/deep-20261018/receipt.json`。旧诊断的失败和暂停样本保留，不计为通过。Controller 独立测试和用户试玩均待验收。

启动夹具退出时报告 5 个 ObjectDB 条目未释放，保留原日志，不能将该启动检查表述为正常关闭或无警告验收。Python 两个工具通过语法检查，`git diff --check` 通过；本轮没有改变此前已验证的生产模拟源码，因此沿用原有 720 步一致性与玩法回归证据。
