# 主角动画修复：本地烘焙与 01 颈部

日期：2026-10-20。工作区：`/Users/apple/ConjoinedTwins-animation`，分支 `fix/character-animation`。

## 根因回顾

- 01 的 Tripo GLB 是“套跑步预设后导出”的版本；Godot 的 `rest_fixer/fix_silhouette` 会把 01 的长颈压进胸腔。
- 关掉 fixer 后，01/02 的 Mixamo 骨架与 Quaternius 动作源的静止朝向不匹配，Idle 手臂上举、Run 变成蹲姿。
- `ground_character` 又用 Run 姿势的骨骼跨度归一化身高，01 被缩到 2.95、02 是 3.43。

## 修复

[build-tools/journey/bake_hero_animations.py](build-tools/journey/bake_hero_animations.py) 在 Blender 5.2 后台模式执行：

1. 导入 `Adventurer_A.glb`，记录 24 个动作每一帧的骨骼**世界矩阵**。
2. 导入主角，把 Mixamo 骨骼和顶点组改为人形名（Hips/Spine/Chest/UpperChest/Neck/Head/LeftUpperArm/LeftHand/LeftUpperLeg/LeftFoot 等）。
3. 用 `target_rest_world @ source_rest_world^-1 @ source_pose_world` 逐帧求目标姿势，只取旋转；髋部不复制源位移，避免把角色压进地面。
4. 新增 `CharacterArmature|Jump`（Idle 姿势 + 髋部起伏 + 屈膝，31 帧）和 `CharacterArmature|HitRecieve_1` 别名。
5. 导出带动画 GLB，包含 27 个 clip。

导入设置：

- `animation/import=true`
- `retarget/bone_map=null`
- `retarget/rest_fixer/fix_silhouette/enable=false`

游戏不再调用 `Adventurer_A` 的运行时动画库；`build_robots` 直接使用 GLB 自带的 `AnimationPlayer`。救援用的 `Climb` / `RopePull` 仍作为额外 library 加入。

身高：主角模型统一 3.45 米；删掉按 Run 姿势归一化的 `bone_span` / `ground_character`，脚底由模型包围盒定位。

## 验证

| 项目 | 结果 |
| --- | --- |
| 固定种子 Idle / Run / Jump 截图 | `builds/anim-review/final/`；01 头/颈恢复，两人同高 |
| `journey_pursuit` | 28 项，0 失败 |
| `journey_combat` | 71 项，0 失败 |
| `journey_failure_presentation` / `journey_rescue_hud` | 全部 0 失败 |
| `check_journey_performance.py` | 26 项全部 PASS，退出码 0；报告见 `~/ConjoinedTwins-perf-reports/character-animation-final/` |
| 生产入口 headless 启动 | 退出码 0 |
| 实际帧时间（M4 / 720p / 关垂直同步 / 180 帧） | 森林 14.97 ms、村庄 8.74 ms、设施 5.87 ms（冷却后） |

## 未完成

- **NPC 动画**：村民、商贩、怪物没有在本轮逐个处理；怪物已有程序化腿动画，静态 NPC 仍需单独盘点。
- `Climb`/`RopePull` 的 `PT.L`/`PT.R` 轨道已改写到 `LeftToes`/`RightToes`；仍需真人试玩确认攀爬脚位。
- Jump 是合成的 31 帧，起跳/落地没有脚部 IK；需要试玩确认节奏。
- 只在 M4 / Metal / 720p 测过；没有真人试玩。
- 没有合入 `test`。
