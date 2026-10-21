# A2 第一步：混音总线与定位音效（未换素材）

日期：2026-10-20。分支：`feature/audio-mix`（从本地 `test@01f1b4d` 新建，独立 worktree `/Users/apple/ConjoinedTwins-a2`）。对应 [质感升级方案](GAME_QUALITY_UPGRADE_PLAN.md) 的 A2。

本步只用仓库已有音效，**没有下载或新增任何音频素材，也还没有背景音乐**。素材替换和分层音乐需用户先同意下载，见文末。

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

## 下一步：需要用户同意下载的素材

以下都是 CC0（公有领域），登记到 `ASSET_SOURCES.md` 后入库；页面没有标注文件大小，下载前会先确认体积（单个新增文件超过 5 MB 另行说明）。

| 用途 | 来源 | 文件 |
| --- | --- | --- |
| 命中、脚步、落地、机关撞击 | Kenney Impact Sounds（130 个，CC0） | `kenney_impact-sounds.zip`，https://kenney.nl/assets/impact-sounds |
| 脚步、武器、拟音 | Kenney RPG Audio（50 个，CC0） | `kenney_rpg-audio.zip`，https://kenney.nl/assets/rpg-audio |
| 章节音乐候选 | OpenGameArt 上标注 CC0 的循环曲（如 Forest Ambience、Dark Forest Theme），逐首核对授权页 | 待用户选定 |

## 待试玩

- 定位音量与衰减距离（固定镜头离角色约 20 米）；合成音效在 3D 下是否刺耳。
- 战斗压低环境声的幅度。
