# 主角步态：跳跃三段、无滑步跑、侧步、持枪分层与双脚贴地

日期：2026-10-20。分支：`art/hero-locomotion`（从 `test@4d86f1f`）。对应《游戏质感升级方案》A4。

只改画面：模拟、碰撞、联机同步不读也不写这里的任何状态（`tests/hero_locomotion.gd` 校验画面刷新前后 `sync_hash()` 不变）。

## 资源：烘焙流程新增四段跳跃

沿用 [HERO_ANIMATION_REPAIR.md](HERO_ANIMATION_REPAIR.md) 的按骨骼朝向重定向流程（`build-tools/journey/retarget_heroes.py`，Blender 5.2 后台），不开 `fix_silhouette`，不下载新动作素材。

动作源没有跳跃，脚本在动作源的世界空间里以 Idle 第 0 帧为底，用关键姿势参数（屈髋、小腿摆角、脚尖、上身前倾、摆臂、侧抬、屈肘）合成四段，与其他动作走同一条重定向：

| 片段 | 帧数 | 关键姿势 |
| --- | --- | --- |
| `Jump_Start` | 7 | 蹲伏蓄力 → 蹬伸、脚尖下压、双臂前上摆 |
| `Jump_Air` | 19 | 蹬伸 → 顶点收腿（左右腿不对称）→ 下落伸腿、双臂侧张 |
| `Jump_Land` | 13 | 着地 → 浅蹲缓冲 → 站直 |
| `Jump_Land_Heavy` | 22 | 着地 → 深蹲缓冲并停留 → 站直 |

踩地姿势在目标骨架上再按正向运动学校正髋高：两套骨架腿长比例不同，只按动作源腿长算下沉会让落地蹲姿脚掌离地约 0.13。校正后两段落地全程脚踝高度与 Idle 相同（偏差 < 0.03）。

重烘焙：

```bash
git show 8fba7a2^:assets/humans/hero_01.glb > /tmp/in_01.glb
/Applications/Blender.app/Contents/MacOS/Blender -b --python build-tools/journey/retarget_heroes.py -- /tmp/in_01.glb assets/humans/hero_01.glb
```

02 同理。输入用重定向前的 Tripo GLB；未改动脚本时重跑与库内 GLB 逐字节相同。新 GLB 约 2.0 MB（原 1.8 MB）。

## 画面层

### 跳跃三段（`journey_view.gd` 的 `sync_journey_character`）

- 离地且竖直速度 > 起跳速度 60%：`Jump_Start`，相位 = (起跳速度 − 竖直速度) / (起跳速度 × 0.4)。
- 其余离地时间：`Jump_Air`，相位从 60% 起跳速度线性走到 −起跳速度；从平台走下或更高处下落时停在伸腿末帧。
- 着地瞬间按本次腾空的最高脚高减去落地地面高度求下落高度：超过普通跳跃顶点 1.25 倍用 `Jump_Land_Heavy`，否则 `Jump_Land`；轻缓冲越轻播得越快（1.0–1.6 倍），重缓冲 0.9–1.1 倍。原有整体压扁缩放减半并随下落强度缩放，避免与屈膝重复。
- 相位均由模拟的 `run.heights` / `run.vertical_speed` 决定，暂停、读档、联机两端一致。

### 无滑步跑

`HERO_STRIDE_SPEED = [4.56, 5.16]`（世界单位/秒）是 Run 片段原速下支撑脚滑过地面的速度，02 腿更长所以更快。播放倍率 = 实际水平速度 / 自然步速（限 0.6–4.0）；实际速度取模拟时间内的真实位移，重试、换章的整段位移不计。旅程里行进速度为 16 单位/秒，倍率约 3.5（01）/ 3.1（02），旧值固定 2.2，会滑步约 6 单位/秒。

脚步声改为按各自 Run 步幅发声（自然步速 × 0.4 秒，01 约 1.8 米、02 约 2.1 米），与画面步频一致；原来统一 1.7 米。

### 侧步/后退混合、持枪分层、双脚贴地（`scripts/hero_locomotion.gd`）

一个 `SkeletonModifier3D`，挂在每名主角的骨架下，在 AnimationPlayer 之后执行，修改不写回动画姿势：

- **侧步/后退**：取消原来的 ±0.42 弧度根节点偏航，身体始终朝前。按实际水平速度方向分解前/后/左/右权重，前后先合成（Run 与 `Run_Back`），再混入 `Run_Left`/`Run_Right`；各片段按 Run 的相位同步（`Run_Left` 与 Run 差半周期）。权重 0.1 秒平滑。前倾改为前进时最大、横移时轻微、后退时近乎直立。
- **持枪上半身层**：拿枪时右臂整链取 `Idle_Gun_Pointing`，左臂和胸口取一半，下半身继续跑。修改器记录修改后的手腕姿势，`journey_combat_view.gd` 用 `final_bone_pose` 读取挂枪，枪不会停在跑步摆臂的位置上。换弹时持枪层不改双臂，交给既有的 `reach_hand` 手部 IK。
- **双脚贴地**：着地行进时对每只脚用 `run.surface_at` 采样脚下地面，与身体所在地面（`run.floor_heights`）的高度差决定抬脚或下探；需要下探时先压低髋部，再两段骨骼 IK，保持动画的屈膝方向和脚掌朝向。高度差超过 0.9 视为台阶边缘外不处理，悬空的缺口不处理。台阶、坡道、升降台都走这一条。
- **让位**：救援（`RopePull`/`Climb`）、受击/死亡、坠落、腾空时贴地与侧步全部关闭，持枪层随枪隐藏立即撤掉。

## 关键姿势截图

不入库，在 `builds/hero-locomotion/`（`.gitignore` 已忽略 `builds/`）：

- `jump_01_side.png`、`jump_02_side.png`（及 `_front`）：Idle、起跳蹲伏、蹬伸、顶点收腿、下落伸腿、轻落地、重落地。
- `strafe_gun_01.png`、`strafe_gun_02.png`：左侧步、右侧步、后退步、持枪层来源姿势。
- `frames/`：单帧原图。

用 `build-tools/journey/preview_clips.py` 在 Blender 后台渲染。运行时的混合、贴地与持枪分层只在游戏里成形，由 `tests/hero_locomotion.gd` 以骨骼数值核对；游戏内可见画面按 work 模式延后到试玩。

## 验证

| 项目 | 结果 |
| --- | --- |
| `tests/hero_locomotion.gd`（新增） | 67 项，0 失败；连续两次 |
| `journey_failure_presentation` / `journey_rescue_transition` / `journey_rescue_hud` / `journey_combat` / `journey_world_view` | 0 失败 |
| `rescue_animation` | 7 项通过；22 条 `rim` 脚本错误与基线相同 |
| `journey_pursuit` | 28 项 0 失败；步频断言由固定 2.2 改为“速度 / 自然步速” |
| `journey_audio_mix` | 59 项 0 失败；脚步距离由 1.8 改为 1.9 米 |
| `check_journey_performance.py` | 26 组全部 PASS，退出码 0；报告 `~/ConjoinedTwins-perf-reports/hero-locomotion-2/` |

既有问题（与本改动无关，基线同样存在）：`journey_touch` “touch cannot request backward movement” 失败。

## 待试玩确认

- 跳跃节奏：起跳段只占 0.12 秒模拟时间，蹲伏是“蹬地瞬间”的姿势，没有起跳前的预备延迟（不改模拟）。
- 3.5 倍步频在 16 单位/秒下是否显得过快；如果觉得太碎，需要调的是移动速度或换步幅更大的跑步动作，而不是重新放开滑步。
- 斜向移动时侧步与前跑混合的腿部交叉感；持枪跑时左臂半摆幅是否自然。
- 台阶边缘、坡道、升降台上的贴地；救援攀爬脚位不受影响。
