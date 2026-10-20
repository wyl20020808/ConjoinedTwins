# 第二轮画面整合

2026-10-20。按用户"按建议顺序做、按思路调整"的指示，六刀从 `test@d6f4c87` 起以线性历史完成，每刀一个任务分支，后一刀从前一刀继续。最终分支为 `art/hazard-readability`（第七刀为用户看图后追加），**尚未合入 `test`**，需要用户授权。

| 刀 | 分支 | 提交 | 内容 | 文档 |
| --- | --- | --- | --- | --- |
| R1 | `art/perf-headroom` | `e0052a1` | 自适应 MetalFX/FSR2 超分、SSAO 降档、去景深、林下层 75 米 | [性能余量](LOOKDEV_R2_PERF_HEADROOM.md) |
| R2 | `art/time-of-day-lighting` | `2464e15` | 清晨/黄昏/夜晚三时段、路灯火把、星空、Screen 晕光 | [时段与发光](LOOKDEV_R2_TIME_OF_DAY.md) |
| R3 | `art/energy-rope` | `e9a8a87` | 青→橙能量绳外壳、能量包、张力/受阻反馈、中点柔光 | [能量绳](LOOKDEV_R2_ENERGY_ROPE.md) |
| R4 | `art/night-mine` | `a8b0acb` | 第三章湿路面与矿车轨道、发光矿晶、厂房窗灯/信标/泛光灯 | [夜间矿道](LOOKDEV_R2_NIGHT_MINE.md) |
| R5 | `art/ground-water` | `42360bf` | 露出河道、流动水面、第二章草地、远景田块 | [河面与草地](LOOKDEV_R2_GROUND_WATER.md) |
| R6 | `art/impact-fx` | `9f75b52` | 冲击波环、瞬时补光、受击色散、拾取光柱 | [打击特效](LOOKDEV_R2_IMPACT_FX.md) |
| R7 | `art/hazard-readability` | 见分支 | 用户反馈机关可见度下降：黄昏改顺光、夜间头灯 | [机关可见度](LOOKDEV_R2_HAZARD_READABILITY.md) |

## 验证

- 六刀每刀都串行运行 `check_journey_performance.py`，26 项全部通过、源码测试期间未变；报告在 `~/ConjoinedTwins-perf-reports/round2-p1` 到 `round2-p6`。
- 生产入口 headless 启动退出码每刀都是 0。
- 第三刀额外运行 `rope_mesh_lifetime`、`journey_rescue_transition`，0 失败。
- 固定种子实机截图在 `builds/round2/`（本地，不入库）。`before-after.png` 是第一轮末与第二轮末同机位的并排对照。

## 帧时间（M4 / Metal / 1920×1080 / 关垂直同步）

`test@d6f4c87` 与本轮最终源码，在同一台机器上交替运行同一基准工具（`builds/round2/tools/bench.gd`）：

| 观察点 | 第一轮末 | 第二轮末 |
| --- | ---: | ---: |
| 森林 | 22.1–24.4 ms | 16.9–19.0 ms |
| 村庄 | 14.8–15.9 ms | 12.2–15.0 ms |
| 矿道 | 11.2–12.1 ms | 10.1–12.1 ms |
| 设施 | 11.0–11.9 ms | 10.5–10.9 ms |

对照时机器已经连续跑了几个小时，处在热降频状态，两边都比冷机时高。冷机下第一刀后森林段约 15 ms。本轮新增了灯光、能量绳、水面和特效，1080p 下整体仍比第一轮末更快，主要靠第一刀的超分和林下层裁剪。

## 仍未完成

- **没有用户试玩**：时段光照、夜景亮度、能量绳亮度、冲击特效强度都只看了定格截图。
- **只在 macOS M4 上测过**；Windows FSR2、网页、iOS 都没有运行。
- **4K 全屏没有测**：内部渲染高度固定约 800 像素，最低 0.34 倍，画面清晰度需要实机看。
- **建议中的第 8 项（界面）本轮未做**：开始页改全屏标题，拾取文字改图标。
- **命中顿帧**涉及模拟时序，没有做。
- `tests/journey_hud_damage.gd` 把证据写到硬编码的 Windows 路径 `D:/ConjoinedTwins-task-temp/`，在 macOS 上 `store_string` 空引用后不退出。这是既有问题，与本轮无关，不在 26 项权威清单内。`tests/speed_guidance_animation.gd` 的既有失败见[第一轮整合](ROUND1_INTEGRATION.md)，本轮未处理。
