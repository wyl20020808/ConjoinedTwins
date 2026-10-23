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

## 种类单一：新增三种怪物、三种村民，全部怪物每章都可能出现并轮换

用户按提示词在 Tripo 生成 6 个模型（来源、大小、SHA-256 见 `ASSET_SOURCES.md`），按用户要求：怪物不按关卡限制，每章都可能出现所有种类，并且交替出现。

**新怪物**（`scripts/journey_monsters.gd`）：

| 种类 | 名称 | 攻击方式 | 血量 | 速度 | 说明 |
| --- | --- | --- | ---: | ---: | --- |
| `root_spider` | 根须蛛 | 扑咬（复用冲锋逻辑） | 30 | 290 | 预警 0.4 秒、扑 0.4 秒、射程 220、伤害 22，短促快速 |
| `goblin_bomber` | 矿灯地精 | 远程（复用飞行物逻辑） | 35 | 200 | 炸药包飞得比箭慢（520），预警 0.8 秒，射程 620，伤害 38；画面为黑色圆弹加发光引信 |
| `river_crab_knight` | 河岸钳甲兵 | 近战砸地 | 90 | 150 | 慢速重甲，落点冲击范围与石卫相同 |

原来按名字写死的判断（`archer`、`dasher`/`wolf`）改为按攻击方式：`Monsters.ranged()`（弓手、地精）与 `Monsters.charges()`（冲锋者、狼、根须蛛），涉及模拟、搭档避险、预警条、画面动作与特效。

**出场编排**：原来每只怪从“弓手 / 冲锋者 / 狼 / 本地怪”袋中抽，本地怪按地貌固定（森林树精、村庄掠袭者、矿道石卫）。现在每一群抽一个主力和一个辅助（都从 9 种的洗牌袋中抽，二者不同），成员按主力、辅助交替站位；相邻两群主力不同，空群不打断轮换。每种怪都可能出现在任何一章。实测 3 个种子 × 3 章：9 种每章都出现，每种 5–18 只，没有一种超过总数四分之一，相邻怪群主力不重复。

**新村民**：渔夫、老矿工、巡逻卫兵加入村民轮换（`scripts/journey_landscape.gd` 的 `VILLAGERS`，由 4 种变为 7 种），与原村民一样有待机、说话、张望动作。

**绑骨**（`build-tools/journey/rig_npcs.py`）：

- 新增 `spider` 骨架：按贴地顶点绕身体中心的角度间隙自动分腿（根须蛛识别为 8 条），每条腿两节拱形骨；动作为三角步态（相邻腿交替抬起前摆）、前腿高举再扑下的攻击、腿收拢的受击。
- 地精举手角度 70°（举太高会拉长手臂网格），钳甲兵走路摆臂幅度降到 30%（大钳是独立网格块）。

## 验证

- `tests/journey_monster_polish.gd`：27 项 0 失败（狼头朝前、转身与侧倾、察觉与出手特效；三种新怪物带五个动作、名称血量与轮换、攻击方式归类、走完蓄力/出手/受击/倒下的画面同步；三种新村民加入轮换并带三个动作）。
- `tests/journey_random_layout.gd`、`tests/journey_combat_variety.gd`：把原“弓手、冲锋者、狼各至少 15 只、三者相差不超过 1”的配比约定改为新设计：每章 9 种都出现，没有一种超过四分之一，相邻怪群主力不同。分别 4536 项、85 项 0 失败。
- `journey_monsters`（347 项）、`journey_world_view`、`journey_environment_lifetime`（无资源残留）、`journey_encounter_density`、`journey_pursuit`、`journey_polish`、`journey_combat`、`journey_hit_feel`、`journey_audio_mix`：0 失败。
- `python3 build-tools/check_journey_performance.py --godot /Applications/Godot.app/Contents/MacOS/Godot`：狼头与特效一轮 26 组全部通过（`/Users/apple/ConjoinedTwins-task-temp/monster-polish-perf-20261021/summary.json`）；新怪物与轮换一轮 26 组全部通过（`/Users/apple/ConjoinedTwins-task-temp/monster-roster-perf-20261021/summary.json`）。
- 新增素材让项目多出约 16 MB（6 个原始导出缩图后约 7.6 MB，绑骨版约 8.6 MB，另有导入时提取的贴图）。网页包体积尚未重新测量。

## 待试玩

- 狼头在游戏里的实际朝向，鬃毛和颈部有没有拉扯变形。
- 察觉光环和奔跑扬尘会不会太密。
- 三种新怪物在游戏里的大小、朝向和动作（根须蛛三角步态、地精抛炸药包、钳甲兵砸地）；新数值（血量、伤害、速度）是否合适。
- 9 种怪物轮流出现后的难度：每章都可能遇到远程地精与重甲钳甲兵。
- 新村民在村庄里的分布与比例（老矿工按普通村民身高显示，可能显得不够矮）。
