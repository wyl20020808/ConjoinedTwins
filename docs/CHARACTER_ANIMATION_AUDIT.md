# 角色动画审计：01 主角变形与动画来源

日期：2026-10-20。工作区：`/Users/apple/ConjoinedTwins-animation`，分支 `fix/character-animation`（从 `test@d6f4c87` 新建，与另一个 Claude Code 工作区隔离）。

**2026-10-20 更新：已按建议路线 1 完成本地烘焙，见 [CHARACTER_ANIMATION_FIX.md](CHARACTER_ANIMATION_FIX.md)。** 以下保留当时的诊断记录。结论是：**01 的问题不是缺动画代码，而是 01 的 Tripo 角色资产在“套跑步预设后导出”时留下了与动画重定向不兼容的颈部/骨架静止姿态**。继续在运行时调参数只会把头部拉飞或把手臂拉成 T 姿势。

## 现状

- 两个主角 GLB 都有 65 根 Mixamo 骨、一个 `run` 动作；`animation/import=false`，游戏实际播放 `Adventurer_A.glb` 的 24 个 Quaternius 动作，导入时用 `bonemap_mixamo.tres` 做 Godot 人形重定向，并开启 `rest_fixer/fix_silhouette`。
- 动作源本身正确：把 `Adventurer_A.glb` 单独渲染，Idle 手臂自然下垂，Run 是正常跑步。
- `Downloads` 里的原始 `stylized adventurer 3d model.glb` / `adventurer girl 3d model.glb` 只有 54 根骨，且蒙皮几乎全部绑在 Hips 上（Tripo 未套动作前的导出），不能直接替换现用 GLB。

## 关键实验

| 条件 | 结果 |
| --- | --- |
| 01 保持 `fix_silhouette=true` | 跑/待机动作正常，但 01 的头被压进胸腔，脖子消失；02 正常 |
| 01 改 `fix_silhouette=false` | 01 头/脖子正常，但两名主角的 Idle 手臂上举、Run 变成蹲姿摆拳——重定向整体错误 |
| 01 头部顶点强制 100% 绑到 Head | 头仍然下沉，说明不是权重，而是 fixer 后的骨骼/绑定关系 |
| 01 网格自动权重 | 头部仍按 fixer 的结果变形 |
| 01 网格绑到 02 的骨架 | 头/身体比例正常，但 Blender 导出后 GLB 没有 `skins`，Godot 里只剩一个空 `GeneralSkeleton` 节点，动画无法驱动 |
| 身高 | `ground_character` 用 Run 姿势的骨骼跨度归一化，01 缩放 2.95、02 缩放 3.43；这是“01 比正常矮”的直接原因。改为按模型包围盒统一 3.45 后两人同高 |

## 根因判断

1. **01 资产**：Tripo 的“套跑步预设再导出”改变了 01 的静止颈部/骨架，Godot 的 `fix_silhouette` 试图把 01 的脖子压到动作源的轮廓，导致头部塌陷；关掉 fixer 后，01 自己的骨骼又和 Quaternius 动作的静止朝向不匹配，动作整体错位。
2. **身高**：`ground_character` 用 Run 姿势的骨骼跨度归一化，两人跑姿不同就被缩成不同身高。
3. **缺失动作**：动作源没有 `Jump`，`play_action("Jump")` 只能回退；NPC 多数是静态 Tripo 网格，没有骨架/动画。
4. **NPC**：本轮未逐个盘点，尚未改。

## 建议的正式修复

不要再在 Godot 运行时打补丁。两条可行路线：

1. **Blender 重定向并烘焙**：用动作源对 01/02 的 Mixamo 骨架逐动作烘焙成局部骨骼轨道，导出带动画的 GLB，导入时关闭 Godot 重定向。可保留 Tripo 外观，也能补 Jump（用跳跃/落地关键帧合成）。
2. **重新生成 01 的绑定**：在 Tripo 重新给 01 做 Mixamo 绑定，导出不带动作的 GLB，只保留干净骨架与权重，再走第 1 条的重定向烘焙。原提示词和账号仍在，可复现。

NPC 动画应作为独立小项：先盘点 `journey_landscape` 的村民、怪物、商贩，给有骨架的补 Idle/Walk，没有骨架的用程序化呼吸/摆动，不混进主角修复。

## 当前状态

- 分支无源码/资产改动，只有本审计文档。
- 实验产生的临时 GLB 与截图在 `builds/anim-review/`（工程外或忽略目录），未入库。
- 没有运行性能套件；本轮没有可交付的运行时改动。
