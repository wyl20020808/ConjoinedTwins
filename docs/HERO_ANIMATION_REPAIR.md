# 主角动作与形态复查修复

日期：2026-10-20。分支：`feature/npc-animation`（从合并第二轮画面后的 `test@0605337` 新建）。

## 复查发现（`test` 上 DP 的烘焙版 `c6eebb6`）

固定种子实机截图（`builds/npc-anim/hero-check/`、`builds/round2/merged/`）：

1. **朝向反了**：游戏机位在角色身后，本应看到背影。烘焙版里 02 正脸朝镜头，01 侧身。DP 自己的验收图 `game-village.png`、`idle-back.png` 也是正脸朝镜头。
2. **Idle 手臂外摊上抬**，像在耸肩。

原因在 `build-tools/journey/bake_hero_animations.py` 的重定向公式：`target_rest @ (source_rest⁻¹ @ source_pose)`。它把源骨骼在**自身局部轴向**里的旋转直接套到目标骨骼上。Quaternius 与 Mixamo 两套骨骼的局部轴向、静止姿势都不同，所以整体朝向和手臂都偏了。另外它在一次求值里设置所有骨骼，子骨骼用的是父骨骼的旧姿势。

## 修复

不再使用烘焙版，回到第一轮已经验证过朝向与姿势的 Godot 导入时重定向，只针对原有的两个问题：

- **01 颈部塌陷**：`hero_01.glb.import` 的 `retarget/rest_fixer/fix_silhouette/filter` 排除 `Neck`、`Head`，其余骨骼照常修正轮廓。
- **两人身高不一致**：`ground_character` 改用 Idle 站姿的骨骼跨度归一化到 3 米。原来用 Run 姿势，两人跑姿不同会被缩成不同身高。
- **仰头**：重定向后两人的颈、头都有约 25° 仰角，近景像在看天。不加过滤时也有，是原管线的偏差。新增 `scripts/hero_head_level.gd`（`SkeletonModifier3D`），在动画求值后把 Neck 压低 0.15、Head 压低 0.32 弧度。

主角模型与导入配置恢复为 `d6f4c87` 版本（只给 01 加了过滤项）。`bake_hero_animations.py` 保留在仓库里，不再使用。

## 已知取舍

- 烘焙版新增的合成 `Jump` 动作随之不再可用。`Jump` 回到原来的 `Roll` 后备，与第一轮一致。
- DP 加的救援动作脚骨改名（`PT.L/PT.R → LeftToes/RightToes`）对重定向后的骨骼是空操作，保留。

## 验证

- 背面、侧面逐动作截图：Idle、Run、Roll、HitRecieve、Gun_Shoot、Death 两人背对镜头，手臂自然，跑步交替步。
- 01、02 头颈特写：`builds/npc-anim/portraits-{nofilter,filter,level}.png`。依次是颈部塌陷、颈部恢复但仰头、平视。
- `check_journey_performance.py` 26 项全部通过，报告在 `~/ConjoinedTwins-perf-reports/hero-fix/`；生产入口 headless 退出码 0。
- 没有真人试玩。

## 环境提示

合并后若主角仍是旧样子，多半是 `.godot` 导入缓存没更新。直接运行游戏不会重新导入资源，需要先执行一次 `Godot --headless --path . --import`。
