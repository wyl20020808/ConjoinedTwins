# 村民与 NPC 待机动画

日期：2026-10-20。分支：`fix/character-animation`。

## 现状

`journey_landscape.gd` 的 `VILLAGERS` 只有四种静态度假模型：

- `villager_farmer.glb`
- `villager_elder.glb`
- `villager_blacksmith.glb`
- `villager_merchant.glb`

四件 GLB 都 **没有 Skeleton3D、没有 AnimationPlayer**，是纯静态网格，无法直接播放骨骼动画。它们通过 `landscape_batch` 的 MultiMesh 批量摆放，每批可能有多个实例，也不适合为每个实例加独立 `AnimationPlayer`。

## 做法

新增 [villager_sway.gdshader](scripts/villager_sway.gdshader)：

- 顶点按高度加权摆动：脚底 `h=0` 保持不动，躯干/头部最大。
- 幅度约 0.022（模型局部单位），以呼吸和重心变化为主，不做走/跑。
- 每个 MultiMesh 实例用 `INSTANCE_CUSTOM.r` 给不同相位，避免整排村民同步摆动。
- 保留原 albedo 贴图；有法线贴图时一并接入，粗糙度固定 0.9。

[journey_landscape.gd](scripts/journey_landscape.gd) 的 `collect()` 对 `villager_*` 路径换成该 ShaderMaterial；`batch_cell()` 为村民批次开启 `use_custom_data` 并写入相位。仍然是 MultiMesh 一批绘制，没有增加实例节点。

## 验证

| 项目 | 结果 |
| --- | --- |
| Shader 编译/运行 | 无 shader 报错 |
| 村民近景两帧差分 | 村民区域 9,487 个像素变化，确认摆动生效 |
| `tripo_village_assets` | 807 项，0 失败 |
| `check_journey_performance.py` | 26 项全部 PASS；报告见 `~/ConjoinedTwins-perf-reports/npc-idle-final/` |
| 生产入口 headless 启动 | 退出码 0 |
| 实际帧时间（M4 / 720p / 冷却后） | 森林 14.17 ms、村庄 7.66 ms、设施 5.92 ms；村民 shader 无可测退化 |

![村民待机](<builds/anim-review/final/villager-a.png>)

## 未完成

- 只有待机摆动，**没有走路、转身、手势、对话动作**。要加这些需要给四件村民重新绑定骨架并烘焙动作，和主角同一条管线。
- 只覆盖 `VILLAGERS` 四种；路边其他静态 NPC 如果后续接入，需要在 `collect()` 的路径判断里扩展。
- 怪物与敌人已有程序化腿部动画，本轮不动。
- 没有真人试玩；只在 M4 / Metal / 720p 测过。
