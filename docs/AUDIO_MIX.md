# A2：混音总线、定位音效与录制音效

日期：2026-10-20。分支：`feature/audio-mix`（从本地 `test@01f1b4d` 新建，独立 worktree `/Users/apple/ConjoinedTwins-a2`）。对应 [质感升级方案](GAME_QUALITY_UPGRADE_PLAN.md) 的 A2。

第一步只用仓库已有音效；第二步经用户同意下载 Kenney 两个 CC0 音效包并替换主要动作音效。**还没有背景音乐**，候选曲目待用户挑选。

## 改动

- **总线**（`scripts/sfx.gd`）：运行时建立 Music / SFX / Ambience / UI 四条总线，都送往 Master；Master 末端加 −0.5 dB 硬限幅，叠音不爆。重复初始化不重复建。
- **随机变化**：每次播放音高 ±5%、音量 ±2 dB，连续枪声和命中不再完全相同。金币、奖品、通关、点击走 UI 总线，其余走 SFX。
- **定位音效**：新增 8 个 `AudioStreamPlayer3D` 轮换池（`play_at`），带距离衰减与左右声像。
  - 机关（`scripts/journey_hazard_fx.gd`）：压机落下、地刺弹出、塌陷开裂与塌落、摆锤开摆、蒸汽加压、火焰弩命中时，在机关位置发声。
  - 敌人（`scripts/journey_enemy_view.gd`）：每次攻击前摇在敌人位置响一声低沉蓄力（同一次攻击只响一次）；命中声改为在敌人位置。
  - 旅程事件（倒树、野猪、推车等）的预警声改为在事件位置发声。
- **战斗压低环境声**（`scripts/journey_view.gd`）：附近 900 单位内有已察觉玩家的存活敌人时，环境总线约 0.4 秒内降到一半（约 −6 dB），脱战后约 1.5 秒恢复。森林、河流、风声与鸟鸣都走 Ambience 总线。

画面上仍不显示任何预警标记；声音只是补充提示，判定时长不变。

## 验证

- 新增 `tests/journey_audio_mix.gd`：29 项 0 失败（总线与限幅、重复初始化、环境声路由、随机变化范围与分布、UI 路由、定位播放位置、敌人前摇只响一次且下次再响、压机落下定位发声、战斗压低与恢复）。
- `python3 build-tools/check_journey_performance.py --godot /Applications/Godot.app/Contents/MacOS/Godot`：26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/audio-mix-perf-20261020/summary.json`。

## 第二步：录制音效（Kenney，CC0）

用户同意后下载 `kenney_impact-sounds.zip`（800,850 字节）和 `kenney_rpg-audio.zip`（964,837 字节），挑 57 个 OGG（约 628 KB）放入 `assets/audio/kenney/`，许可原文一并保存。来源、SHA-256 与用途登记在 `ASSET_SOURCES.md`。

- `scripts/sfx.gd` 新增 `VARIANTS` 音效组，同名多条录音随机选取。
- 脚步（`journey_view.gd`）：贴地每走约 1.7 米一步，按地貌选草地、木板（河道）或石路；起跳和落地各一声，落差大时落地更重。原来旅程里没有起跳、落地声。
- 机关：压机落下改金属重击，地刺弹出改金属轻击，路面开裂改木头吱嘎，塌落改碎石，火焰弩命中改金属板撞击。
- 战斗：命中敌人、击败敌人、自己受击改用拳击录音；换弹开始卸弹匣、结束上膛各一声；合作门打开播放开门声。
- 界面与未替换事件（金币、奖品、通关、救援等）仍用原合成音效。

验证：`tests/journey_audio_mix.gd` 扩展到 47 项 0 失败（各音效组全部加载、随机选取、不足一步不发声、走满一步播放脚步录音、落地录音、压机播放金属重击）；`journey_combat`、`journey_world_view`、`journey_failure_presentation` 0 失败。
- 性能检查第一轮 `journey_environment_lifetime` 失败：测试退出时仍有 OGG 播放句柄（14 个对象）残留。原因是退出场景树后仍触发了脚步声，测试中整段瞬移也被当成走路。修正为退出后不再新建播放，单帧位移超过 3 米视为读档/换章、不算脚步。重跑 `check_journey_performance.py` 26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/audio-kenney-perf-20261020-r2/summary.json`。

## 待试玩

- 定位音量与衰减距离（固定镜头离角色约 20 米）；脚步密度与音量，两人同时走时是否嘈杂。
- 战斗压低环境声的幅度。
