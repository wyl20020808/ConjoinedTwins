# 枪械手感、换枪动作与 Tripo 枪械模型

日期：2026-10-21。分支：`feature/gun-feel-polish`（从 `origin/test@3550e00` 快进）。对应用户反馈：枪的手感差（换弹、战斗都差点意思）；丢枪、捡枪、把枪放回背上、从背上拿下来的动画不完美，希望像传统射击游戏（参考绝地求生）；枪的模型用 Tripo 重做。

## 动作做法：Blender 关键帧片段 + 手部 IK 贴合

按用户要求，动作在 Blender 里按关键帧制作，再导入游戏混合：

- `tools/blender/make_gun_anims.py` 在 `Adventurer_A` 骨架上为上半身制作 14 段片段：收枪 Holster、取枪 Draw、捡枪 Pickup、背枪 Stow、丢枪 Toss、冲锋枪换弹 ReloadMag、喷火器换罐 ReloadTank、霰弹枪逐发装填 ShellStart/ShellLoad/ShellEnd、泵动 Pump、榴弹逐发装填 GrenadeStart/GrenadeLoad/GrenadeEnd。片段里有躯干扭转、弯腰、侧倾和低头看枪，双臂在 Blender 里用两段 IK 摆到枪上后逐帧烘焙。
- 每段导出为 `assets/humans/gun_anims/gun_<片段>.glb`，导入设置与救援动作相同（`bonemap_quaternius.tres` 重定向 + 修正剪影），由 `road_demo.gd` 加进主角的动画库（不循环）。
- 同一脚本把每帧的枪身姿势、背上第二把枪的姿势、双手目标和道具状态写入 `scripts/gun_action_curves.gd`。坐标相对胸口骨骼、按手臂长度归一；游戏里按主角实际手臂长度换算。
- 游戏中 `hero_locomotion.gd` 新增动作层：按模拟时间采样片段，覆盖脊柱、颈、头、肩和双臂（`ACTION_BONES`），下半身继续跑跳；`journey_combat_view.gd` 采样曲线摆枪，再用已有的双臂 IK 把手精确贴到枪的握把和护木上（Blender 骨架与主角比例不同，IK 负责最后的接触）。
- 片段起止都是抱枪姿势；游戏里开火瞄准时，首尾 30% 与当前持枪姿势平滑衔接。
- 预览：`blender -b --factory-startup --python tools/blender/make_gun_anims.py -- <目录>` 会为每段输出正面斜 ¾ 与身后两行、各 6 帧的对照图（带对应的 Tripo 枪）。改动作只需改脚本里的关键帧再运行一次，几十秒出图。

全部动作按模拟记录的开始时间播放（`combat.motion`，随存档恢复，联机两端一致），暂停冻结、重试与回放稳定，不用 Tween 或墙钟时间。

## 换枪、捡枪、丢枪（模拟 `scripts/journey_combat.gd`）

| 动作 | 时长 | 画面 |
| --- | --- | --- |
| 换枪 | 0.55 秒不能开火（原 0.3 秒） | 前 0.25 秒右手把枪抬过右肩放到背上，躯干右转；后 0.3 秒右手伸到背后握住另一把，越过右肩拉回身前，左手最后接上护木 |
| 捡枪拿到手上 | 0.35 秒不能开火（新增） | 弯腰低头，右手伸到右前下方，枪从地上飞进手里，再抬到抱枪位置 |
| 捡第二把背上 | 不影响开火 | 右手继续持枪，左手弯腰从左下方接住第二把，经左肩甩到背上，再回护木 |
| 丢枪 | 背上有枪时共 0.6 秒不能开火 | 向右前方甩出，0.105 秒松手后沿抛物线落到地上的拾取点（落地前地上拾取物隐藏）；背上有枪再接取枪动作 |

动作音效按关键帧触发：甩动风声、枪贴背的闷响、取枪到位的上膛声、丢枪落地的金属撞击。武器面板在取枪期间显示“取枪中”。

## 换弹

- **冲锋枪**：抬枪侧倾、低头看枪；左手拔出空弹匣丢下（弹匣下落）、从左腰弹袋取新弹匣插入，最后拉机柄。Tripo 冲锋枪的弹匣在规整时拆为独立网格，换弹时真的离开枪身。时长不变（1.4 秒）。
- **霰弹枪**：改为逐发装填——起手 0.17 秒，每发 0.33 秒，左手从弹袋取红色弹壳压进装填口；弹仓里有弹时扣扳机直接打断装填开火。面板显示“装填 3/6 · 开火可打断”。
- **榴弹发射器**：同样改为逐发塞进弹巢（起手 0.25 秒、每发 0.43 秒，装满 4 发约 2 秒，与原整装时长相当），枪口上扬。
- **喷火器**：左手握住燃料罐拧松、到腰间换罐再装回，伴随泄压声。

## 射击手感

- 连射热度：每发累积、停火回落；冲锋枪越打枪口越往上走，霰弹枪和榴弹单发顶得很高；每发带少量左右抖动。
- 霰弹枪每发之后泵动：左手后拉护木再推回，此时抛出红色弹壳并有两声金属声；空仓装填完毕后同样泵动一次。冲锋枪抛黄铜弹壳，喷火器与榴弹不抛壳。
- 枪口焰大小按枪种区分；冲锋枪枪声下叠一层短促的枪机金属声。
- 弹匣与备弹全空时扣扳机，每 0.3 秒一声空膛击发声。
- 镜头仍按项目规则不晃动。

## Tripo 枪械模型

四把枪均在用户的 Tripo Studio 账号中文生 3D（H3.1、2K PBR、三角面、上限 2 万面），经 `build-tools/journey/process_tripo_weapons.py`（Blender）规整：枪口 -Z、右手握把对齐 `GRIP_RIGHT`，写入枪口、弹匣、左手握点、装填口、拉机柄标记点，冲锋枪拆出弹匣网格；贴图缩到 1024，每把约 1.6–1.9 MB、约 1.9 万三角面。画面按标记点放置左手、枪口焰和装填位置。来源、提示词与哈希见 `ASSET_SOURCES.md` 与 `build-tools/journey/tripo-weapon-assets.json`。

## 验证（执行者自测，macOS / Apple M4 / Godot 4.7.1）

- 新增 `tests/journey_gun_feel.gd`：逐发装填计时与打断、整匣换弹时长、换枪/丢枪/捡枪冷却与动作记录、存档恢复与旧数据补齐、Blender 片段载入并在收枪/取枪时驱动上半身层、画面上收枪→取枪两段、丢枪落地前隐藏地面拾取物、换弹左手离开护木、泵动左手后拉；0 失败。
- 按新设计改写的旧断言：`journey_combat`（捡枪后 0.35 秒才能开火）、`journey_polish`（弹匣可拆、拔出、丢枪先抛出再隐藏）。
- 回归 0 失败：journey_combat、journey_dual_weapon、hero_locomotion、journey_polish、journey_playtest_feedback、journey_settings_menu、journey_hit_feel、journey_audio_mix、journey_failure_presentation、journey_rescue_transition、journey_rescue_hud、journey_combat_variety、journey_monsters、journey_combat_online、combat_trial_replay、journey_rescue_lifecycle。`journey_hud_damage` 检查项无失败，但收据写入硬编码的 Windows 路径 `D:/...`，在 Mac 上报错，与本次改动无关。
- `python3 build-tools/check_journey_performance.py --godot /Applications/Godot.app/Contents/MacOS/Godot`：报告 `/Users/apple/ConjoinedTwins-task-temp/gun-feel-perf-20261021b/summary.json`。唯一未通过项为 `journey_pursuit` 退出时的 10 个对象 / 3 个资源泄漏告警；同一测试在未改动的 `origin/test@3550e00` 上产生完全相同的告警（日志 `/Users/apple/ConjoinedTwins-task-temp/baseline-journey_pursuit.log`），属既有问题。第一轮运行中 `journey_runtime_budget` 第一章 16000 米追击 p95 5.2 ms 超限一次，第二轮通过，基线也通过，判断为计时波动，待复核。
- 画面：`tests/capture_gun_feel.gd` 在真实渲染下截取抱枪、瞄准、换枪、换弹、泵动、丢枪、捡枪、背枪对照图（正面斜 ¾ 与游戏镜头方向），保存在工程外 `/Users/apple/ConjoinedTwins-art-assets/tripo-weapons-20261021/review/poses3/`；Blender 片段预览在同目录 `review/blender/`。这些是执行者自查截图，不代表用户试玩验收。
- Controller 独立测试未运行（`tests=[]`）；真实键鼠/手柄输入与持续帧率待用户试玩。

## 待试玩

- 收取枪、捡枪、丢枪和各枪换弹在实际游戏镜头距离下的观感；主角手部造型偏大，换弹细节在远景里可能不明显。
- 换枪 0.55 秒、捡枪 0.35 秒的取枪延迟在战斗里是否合适。
- 霰弹枪、榴弹逐发装填与打断是否顺手。
- Tripo 模型的大小、握持位置与贴图在游戏光照下的效果。
