# 怪物表现：狼头摆正、特效补充、转身与侧倾

日期：2026-10-21。分支：`feature/monster-variety`（从本地 `test@3bd21d8`）。对应试玩反馈“怪物特效少了一些，动作可以进一步优化，狼的头是歪着的，怪物种类太少”。

## 狼头歪斜

不是绑骨或动作的问题：Tripo 生成的 `assets/monsters/grey_wolf.glb` 本身头部向一侧扭了约 99°（鼻尖朝身体侧面）。`build-tools/journey/rig_npcs.py` 新增 `straighten_head`：绑骨前，在头部前段找离头顶中心水平最远的鼻尖，求出与身体前方的夹角；再把头颈顶点绕颈根竖轴转回正前方。转动权重随“比颈根更靠前”和“高于胸口”平滑增加，前腿和胸口下半部分不动。只对配置了 `straighten_head` 的模型生效（目前只有狼）。重新生成的 `assets/monsters/rigged/grey_wolf.glb` 头部侧向伸出由 0.32 降到 0.18（身体半宽约 0.16），最前端到身体最前方。

重生成命令：

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python build-tools/journey/rig_npcs.py -- <输出目录> grey_wolf --preview
```

## 动作（`scripts/journey_enemy_view.gd`）

- **转身平滑**：画面朝向以每秒 9 倍的系数追随模拟朝向，不再瞬间转向；暂停时不转。
- **转弯侧倾**：按转身角速度向内侧倾，最多约 12°；站着转身时只保留三分之一。
- 只改画面，碰撞、判定、联机都不变。

## 特效（同一文件 `monster_fx`）

全部按模拟状态的变化沿触发一次，只给离玩家 900 单位以内的敌人，远处不占粒子池：

- **察觉玩家**：脚下扬尘，加一圈按种类着色的光环（树精苔绿、掠袭者橙、石卫冰蓝、弓手黄绿、冲锋者红、狼金黄）。
- **奔跑扬尘**：狼、冲锋者、树精移动时每 0.28 秒扬一次尘；冲锋、扑咬途中每 0.08 秒拖尘。
- **近战出手**：掠袭者、树精、石卫进入出手阶段时，在落点冲击并溅碎屑（石卫冲击范围更大）。
- **弓手放箭**：手部火花。

## 种类单一

已写好 Tripo 文生 3D 提示词：3 种新怪物、3 种 NPC，含生成参数和文件名，见 [TRIPO_PROMPTS_MONSTERS_NPC.md](TRIPO_PROMPTS_MONSTERS_NPC.md)。等用户生成并下载后再接入：绑骨、出生规则，以及每种地貌两种本地怪、相邻敌群交替出现。

现在不调整出场编排的原因：`tests/journey_random_layout.gd` 要求每章远程、冲锋、狼三类数量相差不超过 1。只有 6 种怪时，重排也只是同样几种轮换，体验改善有限。新怪到位后再一起改编排，并相应更新这条配比约束。

## 验证

- 新增 `tests/journey_monster_polish.gd`：12 项 0 失败（狼头朝前、转身逐帧追随与侧倾、约 2 秒转到位、察觉与出手特效各触发一次、下次出手再触发、远处不触发）。
- `journey_hit_feel`、`journey_monsters`（338 项）、`journey_world_view`（44 项）、`journey_combat_variety`（67 项）、`journey_audio_mix`：0 失败。
- `python3 build-tools/check_journey_performance.py --godot /Applications/Godot.app/Contents/MacOS/Godot`：26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/monster-polish-perf-20261021/summary.json`。

## 待试玩

- 狼头在游戏里的实际朝向，鬃毛和颈部有没有拉扯变形。
- 察觉光环和奔跑扬尘会不会太密。
