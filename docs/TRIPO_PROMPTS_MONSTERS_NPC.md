# Tripo 文生 3D 提示词：新怪物与 NPC

日期：2026-10-20。用于“怪物种类太少、总是那几种”的反馈。用户在自己的 Tripo Studio 账号生成并导出，下载后放到下文的文件名，Agent 再接入。

## 生成参数（与已入库的六种怪物、四种村民保持一致）

- 模型：H3.1 高精度；关闭超清几何；关闭分部件生成。
- 纹理：开启，2K，去光处理（de-light），PBR。
- 拓扑：三角面，面数上限 6000。
- 导出：GLB。不需要 Tripo 自带的骨骼和动画（项目用 `build-tools/journey/rig_npcs.py` 自动绑骨并写动作）。

## 通用要求（已写进每条提示词）

单个角色，站在平地上，正面朝前，不带底座、地面、背景和文字；双足角色手臂略微离开身体（便于自动绑骨），双脚平放、分开；四足角色四条腿清楚分开。风格与现有资产统一：写实偏风格化的奇幻冒险游戏角色，手绘感 PBR 材质，轮廓清楚，颜色不要太暗，固定纵深镜头下从背后远处也能认出来。

---

## 怪物 1：根须蛛（森林，第一章）

- 文件：`assets/monsters/root_spider.glb`
- 玩法设想：贴地快速包抄，短距扑咬，体型比狼矮，成群 2–3 只出现。

```text
A stylized fantasy forest monster for a third-person adventure game: a low, wide spider-like creature made of twisted tree roots and dark bark, six thick root legs clearly separated and planted on flat ground, a round mossy body with small glowing amber eyes, a few hanging vines and tiny mushrooms on its back, sharp wooden mandibles at the front. Hand-painted PBR textures, earthy brown and moss green with warm amber glow, readable silhouette, clean game-ready model, single character, standing pose, facing forward, no base, no ground, no background, no text.
```

## 怪物 2：矿灯地精爆破手（矿道，第三章）

- 文件：`assets/monsters/goblin_bomber.glb`
- 玩法设想：远处停下，抛掷有抛物线的炸药包，落点有预警；近身时后撤。

```text
A stylized fantasy goblin miner bomber for a third-person adventure game: a small hunched goblin with grey-green skin, big pointed ears, wearing a dented iron mining helmet with a lit oil lantern on top, leather apron with a belt of round black bombs with short fuses, holding one bomb raised in the right hand, thick work boots. Arms held slightly away from the body, feet flat and apart on the ground. Hand-painted PBR textures, rusty orange and soot grey with a warm lantern glow, readable silhouette, clean game-ready model, single character, standing pose, facing forward, no base, no ground, no background, no text.
```

## 怪物 3（可选）：河岸钳甲兵（河道，第二章）

- 文件：`assets/monsters/river_crab_knight.glb`
- 玩法设想：举起大钳格挡正面子弹，侧面或背后才能打伤，节奏慢、血厚。

```text
A stylized fantasy river monster for a third-person adventure game: a sturdy upright crab warrior standing on two thick armored legs, wide blue-grey shell like a knight's breastplate, one huge raised claw used as a shield and one smaller claw, barnacles and river weeds on the shell, small eye stalks. Arms held slightly away from the body, feet flat and apart on the ground. Hand-painted PBR textures, slate blue, wet teal and coral red accents, readable silhouette, clean game-ready model, single character, standing pose, facing forward, no base, no ground, no background, no text.
```

---

## NPC 1：渔夫（河道，第二章）

- 文件：`assets/landscape/villager_fisher.glb`
- 用途：河岸渡口、水车栈道两侧布景，待机、说话、张望动作。

```text
A stylized fantasy village fisherman NPC for a third-person adventure game: a weathered middle-aged man with a short grey beard, wide straw hat, rolled-up linen shirt, waterproof oilskin apron, tall rubber boots, a wicker fish basket on his hip and a short fishing rod held loosely in the left hand. Arms held slightly away from the body, feet flat and apart on the ground. Hand-painted PBR textures, warm straw yellow, faded blue and brown leather, friendly expression, readable silhouette, clean game-ready model, single character, standing pose, facing forward, no base, no ground, no background, no text.
```

## NPC 2：老矿工（矿道，第三章）

- 文件：`assets/landscape/villager_miner.glb`
- 用途：矿场入口、遗迹回廊两侧布景。

```text
A stylized fantasy old dwarf-like miner NPC for a third-person adventure game: a stocky elderly man with a big braided white beard, leather miner cap with a small candle lamp, patched canvas overalls, thick gloves, a pickaxe resting on his right shoulder, a small lantern hanging from the belt. Arms held slightly away from the body, feet flat and apart on the ground. Hand-painted PBR textures, dusty brown, dark iron and warm lamp orange, kind tired expression, readable silhouette, clean game-ready model, single character, standing pose, facing forward, no base, no ground, no background, no text.
```

## NPC 3（可选）：巡逻卫兵（村庄，第一、二章）

- 文件：`assets/landscape/villager_guard.glb`
- 用途：村口防御、旧桥防线两侧布景，与怪物区分（友方配色）。

```text
A stylized fantasy village guard NPC for a third-person adventure game: a young woman in a padded blue-and-white tabard over light chain mail, simple open iron helmet, a long spear held upright in the right hand, a round wooden shield with a painted sun emblem on the left arm, leather boots. Arms held slightly away from the body, feet flat and apart on the ground. Hand-painted PBR textures, clean blue, white and polished steel, confident friendly expression, readable silhouette, clean game-ready model, single character, standing pose, facing forward, no base, no ground, no background, no text.
```

---

## 交付方式

把导出的 GLB 按上面的文件名放到项目目录（或任意文件夹后告诉 Agent 路径）。Agent 会：缩贴图到 1024、用 `rig_npcs.py` 绑骨与写动作、核对朝向与比例、登记来源（Tripo 授权按账号套餐，由用户确认）、接入出生规则与布景并补测试。至少需要“怪物 1 或 2”中的一个和“NPC 1 或 2”中的一个；可选项有就一起接。
