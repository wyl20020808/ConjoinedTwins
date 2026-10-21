# A1 失败—重试循环提速

日期：2026-10-20。分支：`feature/fast-retry`（从本地 `test@01f1b4d` 新建，独立 worktree `/Users/apple/ConjoinedTwins-a1`）。对应 [质感升级方案](GAME_QUALITY_UPGRADE_PLAN.md) 的 A1。

## 原来

撞击失败演出 1.6 秒、坠落 2.6 秒全部播完，才在屏幕中央弹出大面板，再按回车或按钮从存档继续；空格无效。保存存档时没有任何提示。

## 改动（`scripts/journey_view.gd`）

- **提前确认**：失败 0.6 秒后即可按空格、回车或主按钮从存档继续；前 0.6 秒不接受确认，避免跳跃时误触。判定使用模拟死亡时间 `death_time`，联机两端在同一帧生效。若不按键，演出照常播完。
- **底部失败条**：失败时面板改为屏幕下方 640 像素宽的紧凑条（标题为失败原因，24 号字），不再盖住仍在播放的演出；没有存档时主按钮写“从起点重试”。
- **恢复转场**：从存档恢复后黑场 0.25 秒淡入。只是画面转场，位置与判定已由原快照恢复完成。
- **存档提示**：新存档出现时，暂停按钮下方显示 0.8 秒“已存档”，并播放一声轻音；恢复到同一存档不重复提示。
- 面板排版移到每帧界面状态更新之后，并先给自动换行文字设定宽度再计算高度，修正首帧文字宽度为 1 像素时面板被撑高、遮住触屏按钮的问题。

## 验证

- 新增 `tests/journey_fast_retry.gd`：17 项 0 失败（误触保护、0.6 秒后显示失败条、失败条位置、空格恢复到存档站位、淡入起止、存档提示出现/消失/不重复、无存档时整关重试）。
- `journey_failure_presentation`、`journey_rescue_hud`、`journey_rescue_lifecycle`、`journey_rescue_transition`、`journey_combat`：0 失败。
- `python3 build-tools/check_journey_performance.py --godot /Applications/Godot.app/Contents/MacOS/Godot`：26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/fast-retry-perf-20261020-r2/summary.json`。第一轮曾因上面的面板撑高问题使 `journey_combat` 的三指触屏检查失败，修正后重跑通过。

## 待试玩

- 0.6 秒的误触保护是否合适；底部失败条在手机竖屏下的位置。
- 黑场淡入和“已存档”提示的观感；联机两端按键跳过是否同步。
