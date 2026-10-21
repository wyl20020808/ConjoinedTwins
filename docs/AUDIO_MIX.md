# A2：混音总线、定位音效、录制音效与章节音乐

日期：2026-10-20。分支：`feature/audio-mix`（从本地 `test@01f1b4d` 新建，独立 worktree `/Users/apple/ConjoinedTwins-a2`）。对应 [质感升级方案](GAME_QUALITY_UPGRADE_PLAN.md) 的 A2。

第一步只用仓库已有音效；第二步经用户同意下载 Kenney 两个 CC0 音效包并替换主要动作音效。第三步按用户选定的组合下载四首 CC0 曲目，接入章节音乐与战斗层。

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

用户同意后下载 `kenney_impact-sounds.zip`（800,850 字节）和 `kenney_rpg-audio.zip`（964,837 字节），挑 57 个音效放入 `assets/audio/kenney/`，许可原文一并保存。原始 OGG 用 macOS `afconvert` 解码为单声道 16 位 WAV（约 2.6 MB），原因见下方性能检查记录。来源、SHA-256 与用途登记在 `ASSET_SOURCES.md`。

- `scripts/sfx.gd` 新增 `VARIANTS` 音效组，同名多条录音随机选取。
- 脚步（`journey_view.gd`）：贴地每走约 1.7 米一步，按地貌选草地、木板（河道）或石路；起跳和落地各一声，落差大时落地更重。原来旅程里没有起跳、落地声。
- 机关：压机落下改金属重击，地刺弹出改金属轻击，路面开裂改木头吱嘎，塌落改碎石，火焰弩命中改金属板撞击。
- 战斗：命中敌人、击败敌人、自己受击改用拳击录音；换弹开始卸弹匣、结束上膛各一声；合作门打开播放开门声。
- 界面与未替换事件（金币、奖品、通关、救援等）仍用原合成音效。

验证：`tests/journey_audio_mix.gd` 扩展到 47 项 0 失败（各音效组全部加载、随机选取、不足一步不发声、走满一步播放脚步录音、落地录音、压机播放金属重击）；`journey_combat`、`journey_world_view`、`journey_failure_presentation` 0 失败。
- 性能检查第一轮 `journey_environment_lifetime` 失败：测试退出时仍有 OGG 播放句柄（14 个对象）残留。原因是退出场景树后仍触发了脚步声，测试中整段瞬移也被当成走路。修正为退出后不再新建播放，单帧位移超过 3 米视为读档/换章、不算脚步。重跑 `check_journey_performance.py` 26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/audio-kenney-perf-20261020-r2/summary.json`。

## 第三步：章节音乐（OpenGameArt，CC0）

用户选定：第一章 TinyWorlds《Forest Ambience》，第二章 Komiku《Village, 2018》，第三章 congusbongus《Cathedral in the Forest》，战斗层 Ferk 循环版《Cynic Battle Loop》（原曲 Alex Smith / cynicmusic）。四个文件合计约 8.4 MB，放在 `assets/audio/music/`，导入设置开启循环；来源、大小、SHA-256 登记在 `ASSET_SOURCES.md`，F1 素材署名列出全部作者。

`scripts/journey_view.gd` 的 `pump_music`：

- 探索层按章节选曲，走 Music 总线（−16 dB）；游玩时满音量，开始页、失败与结算降到一半，暂停时冻结。换章时先淡出，再换曲淡入。
- 战斗层（−15 dB）：附近 900 单位内有察觉玩家的存活敌人时约 0.8 秒淡入，探索层同时降到 0.6；脱战后约 3 秒淡出并原地暂停，下次战斗接着放。
- 退出时停止并释放两个音乐播放器。

验证：`tests/journey_audio_mix.gd` 共 59 项 0 失败，本步新增：四首都按循环导入、Music 总线、第一章选曲、战斗层淡入淡出与暂停、换章换曲、暂停冻结、同帧定位池上限。

性能检查前两轮 `journey_environment_lifetime` 都因退出时音频对象残留而失败，逐项排查后修正三处：

1. 暂停中的音乐播放器要先恢复再停止，否则 OGG 播放对象残留。
2. 超出 90 米听距的定位音效不再播放。残留总是远处机关（多排地刺）的声音：这类播放在停止时没有被音频服务器回收。
3. 每个播放器每帧最多启动一次，同帧超出池容量的声音丢弃。

另外，为避免短音效依赖 OGG 解码，把 57 个 Kenney 音效解码为 WAV。修正后环境生命周期测试连续 4 次无残留，`check_journey_performance.py` 26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/audio-music-perf-20261020-r3/summary.json`。第二步提交 `d942cf9` 时那一轮通过属于偶然，残留问题已在本次修正。

## 待试玩

- 定位音量与衰减距离（固定镜头离角色约 20 米）；脚步密度与音量，两人同时走时是否嘈杂。
- 战斗压低环境声的幅度；音乐与音效的音量比例。
- 《Village, 2018》页面没说明可无缝循环，首尾衔接处是否有跳变。
- 战斗层淡入淡出的时机，是否频繁切换。
