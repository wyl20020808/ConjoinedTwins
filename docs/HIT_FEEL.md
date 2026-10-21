# A3 命中与受击手感（固定镜头下）

日期：2026-10-20。分支：`feature/hit-feel`（从本地 `test@01f1b4d` 新建，独立 worktree `/Users/apple/ConjoinedTwins-a3`）。对应 [质感升级方案](GAME_QUALITY_UPGRADE_PLAN.md) 的 A3，按用户确认：镜头不晃动，受击用短暂色散，设置里可关。

## 原来

已有枪口焰、曳光、弹壳、命中碎屑、击败余烬、敌人预警红边、枪械后坐和受击红边。受击色散跟红边一起衰减约 0.4 秒，队友受击也会触发；敌人命中只有小幅后仰；没有手柄或手机震动，也没有开关。

## 改动

- **受击色散**（`scripts/journey_vignette.gdshader`、`scripts/journey_view.gd`）：色散改用独立的 `impact` 参数，只在本机角色受击时触发，约 0.05 秒（3 帧）结束；红边和低血量暗角保持原样。
- **命中停顿**（`scripts/journey_enemy_view.gd`）：被击中的敌人保持当前姿势 50 ms，击败时 90 ms，之后按模拟时间继续。只冻结该敌人的画面，模拟、联机和其余画面照常推进。
- **画面击退与放大**：敌人沿远离两人中点的方向后移最多 0.28 米（击败时 1.4 倍），0.2 秒回位；命中瞬间放大 8% 再回弹。碰撞和判定仍按模拟位置，联机不受影响。
- **击败音效**：原命中音之外追加一层低沉落地声，与普通命中区分。
- **触觉**：本机受击（强）、击败敌人（短）、重落地（弱）、合作门打开（中）时，手柄 `Input.start_joy_vibration`，触屏设备 `Input.vibrate_handheld`。只在本机执行，不进入联机状态。
- **开关**：暂停菜单新增“画面冲击与震动：开/关”，保存在 `user://settings.cfg` 的 `feel/impact_effects`；关闭后不做色散和震动。

## 验证

- 新增 `tests/journey_hit_feel.gd`：15 项 0 失败（队友受击不触发本机冲击、色散 3 帧内结束、关闭开关与保存、暂停菜单显示开关、敌人画面击退方向、放大、停顿期间姿势不变、0.2 秒后回到模拟位置与原尺寸）。测试会写入并还原本机 `user://settings.cfg`。
- `journey_combat` 71 项、`journey_world_view` 44 项 0 失败。
- `python3 build-tools/check_journey_performance.py --godot /Applications/Godot.app/Contents/MacOS/Godot`：26 组全部通过，报告 `/Users/apple/ConjoinedTwins-task-temp/hit-feel-perf-20261020/summary.json`。

## 与方案的差异

方案原写“敌人受击击退放在模拟层”。实现时改为纯画面击退：效果相同，但不改模拟，避免确定性测试与联机指纹回归。

## 待试玩

- 停顿与击退幅度是否够、是否影响瞄准判断。
- 手柄与手机震动强度（headless 无法验证，需实机）。
- 3 帧色散是否看得出来。
