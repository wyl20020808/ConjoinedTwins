# 主角动作与形态修复

日期：2026-10-20。分支：`feature/npc-animation`。

## 现象

- DP 烘焙版（`c6eebb6`）：角色正脸朝镜头，Idle 手臂外摊上抬。
- 第一次修复（`01b209d`，回到 Godot 导入时重定向 + 颈部过滤 + 压头修正）：从背后看正常，但用户试玩发现**手部动作不对**。正面特写证实 01 双手抬到下巴前交叉，02 双臂背到身后。之前的检查只从背后和侧面拍，手臂被身体挡住，没有发现。

## 根因

动作源 Quaternius Adventurer 与 Tripo 主角的 Mixamo 骨架，**各骨骼的局部轴向不同**。不管是 Godot 的 `BoneMap + rest fixer`，还是 DP 脚本里的 `target_rest @ source_rest⁻¹ @ source_pose`，都是按局部旋转搬运动作。轴向一不同，肩、肘的旋转就被套到别的方向上，手跑到胸前或背后。

## 修复：按骨骼朝向重定向（`build-tools/journey/retarget_heroes.py`）

在 Blender 后台按"世界空间朝向匹配"重新烘焙：

1. 对动作源每根骨，计算它这一帧在世界空间相对静止姿势的旋转增量 D，用 D 转动它的静止骨段（本关节 → 子关节），得到肢体这一帧实际指向。
2. 主角骨架自上而下处理：
   - 脊柱、颈、肩、上臂、前臂、大腿、小腿：只做最小旋转，让骨段指向与动作源相同；
   - 髋、头、手、脚：沿用动作源的世界旋转增量。
3. 髋部位移以 Root 为参照、按身高比例保留，倒地和翻滚需要。
4. 救援用的 `Climb`、`RopePull` 也一起烘焙进主角 GLB。
5. 骨骼改为 Godot 人形名（`LeftHand` 等），手部 IK 代码不用改。

全程只用关节位置与世界旋转，与两套骨骼各自的局部轴向无关。

游戏侧：

- `hero_0x.glb.import` 改为导入动画、不做重定向；
- 主角模型转半圈（烘焙后面朝 +Z），保证背对镜头；
- 删除 `hero_head_level.gd`，新方案没有仰头问题；
- `ground_character` 继续按 Idle 站姿统一身高。

## 验证

- Blender 逐动作正面、侧面预览：`builds/npc-anim/hero-bake/sheet.png`。Idle 手臂自然下垂，Run 交替摆臂，射击手臂前举，拉绳双手在身前。
- 游戏内正面特写（Idle、Run 各 4 帧）：`builds/npc-anim/hero-check/zoom.png`，无交叉、无背手。
- 游戏机位截图：`builds/round2/hero-bake/heroes.png`，两人背对镜头、同高。
- 检查与测试结果见提交说明。

## 已知取舍

- 动作源没有 `Jump`，跳跃曾回退为 `Roll`；现已合成跳跃三段，见 [HERO_LOCOMOTION.md](HERO_LOCOMOTION.md)。
- 手指不跟随动作，保持静止姿势。
- 骨段只匹配方向，前臂和手腕的扭转来自动作源的世界增量，个别动作手腕角度可能略有偏差。
- 没有真人试玩。
