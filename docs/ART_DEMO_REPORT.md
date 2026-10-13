# 归航 Demo 本轮实施与验证报告

任务 t01-road-depth-art-demo，原 Run a95c93e3-d954-4bb6-abe6-fddb96abbdf2。执行者在原项目直接实施；没有更改 Controller Plan 或模型配置，没有启动其他 Run、后台写入进程、桌面交互、提交、推送或发布。

## 实际实现

默认入口改为 `scenes/road_demo.tscn`。采用固定透视 3D 底层表现 2.5D 道路滑行：镜头朝向、位置、俯角与 FOV 恒定，道路沿单一方向平移，玩家只横向操作。逻辑位置使用地面单位，20 单位换算 1 米；渲染、HUD、模型与障碍坐标统一换算，鼠标指令不保留。

450 米自动推进道路分为三个连续短区段。两台实际下载的 Quaternius 机甲、七种选用 Kenney 工业 GLB 及原贴图接入场景；程序补齐道路、栏杆、灯带、门架、屏障和界面。两个不同轮廓机器人使用自然静态 Idle 姿态与滑行底座，未开发动作系统。固定灯光、接地阴影、近大远小、侧边建筑、设施和远景均已在真实运行画面检查。

`road_run.gd` 实现自动前进、横向操作、确定性前视避障 AI、本地双人、共同失败/重试和双人共同终点，直接复用原 `link_motion.gd` 的固定步扫掠及连接约束。双方不穿墙，不通过瞬移或关闭约束完成。开始/暂停/失败/结束 UI 均使用道路背景，R 从全段起点共同重试。

恢复材料见 `ART_DEMO_RECOVERY.md`。原六份生产脚本、旧场景、旧测试断言与历史结果保持；新测试与旧 65 项有明确边界，没有删除断言后声称原结果继续有效。

## 执行者验证

修复后最终 `rtk proxy python build-tools/package_macos.py` 退出码 0。证据目录为 `builds/macos/evidence-20261012T091835175791Z/`，`run.json` 保存所有命令、退出码与日志。该入口依次执行 headless 导入、导出、包验证、实际 ZIP 提取 PCK 的隔离加载，以及新的生产路线验证。此前证据目录保留为历史。

新验证命令：

```powershell
rtk proxy "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:/ConjoinedTwins" --script res://tests/road_headless.gd --log-file "D:/ConjoinedTwins/tests/road-headless.log"
```

修复后 33 项全部通过、退出码 0，模拟无失败用时 74.999999999997 秒（显示 75.0）。原 18 项保留，新增屏障显示体积/地面投影与碰撞范围一致，以及两角色接近前不误判、接触前缘失败、左右边界外擦边可通过/内擦碰失败、共同重试等 15 项。覆盖开始页不自动启动、双方自动推进、暂停位置/计时冻结、模式切换无瞬移、连线极限、双人独立输入、道路边界、真实生产场景正常输入与 AI 完成、每步碰撞/连线合法、固定镜头、AI 确定性、任一角色碰撞失败、扫掠无穿透、共同重试和双方共同终点。普通通关路线最大间距约 130 地面单位（6.5 米）；单独反向输入检查达到 220 单位极限。通关只发送输入，终点/屏障专项条件测试明确使用隔离位置夹具，不当作通关证据。

首轮 16 项测试中“双人输入”断言误设对称位置前提：切换前 AI 已移动，生产切换应保持位置。改为相对切换前位置的双向位移检查后通过，未放宽生产连接或碰撞。后续加入每步合法性与固定镜头检查，最终为 18 项。`tests/road_result.json` 和包证据的 `headless-result.json` 保存最终结果及原始源码 SHA256。

真实隐藏渲染命令 `rtk proxy python build-tools/capture_hidden.py` 退出码 0，修复后保存十一张生产画面，增加屏障接近、失败、接触细节和共同重试。执行者已实际读取图片并修复建筑比例、贴图、门架遮挡和 HUD；本次补齐完整危险体积、地面边界和连续港区远景，详细审查见 `ART_DEMO_VISUAL_REVIEW.md`。接触细节图明确只隐藏失败菜单供查看，失败状态与生产位置不变；标准失败 UI 图同时保存。所有最终源码、截图和包的对应证据汇总到 `ART_DEMO_EVIDENCE.json`。

## 新 Mac 包

- 路径：`builds/macos/ConjoinedTwins-macOS-universal.zip`
- 版本：0.2.0；Godot `4.7.1.stable.official.a13da4feb`。
- 包大小：61,170,971 字节（约 58.34 MiB）。
- SHA256：`c1a963299525134808af01a944f056c6728545b63bc968a8800938b7a4d97711`
- 应用：`共生连线 · 归航 Demo.app`；bundle id 延用现有 `org.conjoinedtwins.whitebox`，应用名与入口已更新。
- 架构：arm64 + x86_64；最低系统声明沿用 Intel macOS 11 / Apple Silicon macOS 13。
- ZIP CRC、Info.plist 与入口、Unix `0o100755` 执行权限通过。
- 实际 Mach-O 两架构 CodeDirectory 均包含 CS_ADHOC，SHA256/SHA1 代码页哈希与 Info.plist/CodeResources 特殊槽验证通过；资源封印 SHA256 检查通过。
- PCK 全部资源 MD5 验证，两个机甲、七种 GLB、共享贴图、新入口与三份生产脚本依赖检查通过；制作目录、测试、文档、Windows 脚本与旧白盒未进入 PCK。
- 从实际 ZIP 提取 PCK 在隔离目录用 Windows headless 引擎加载退出码 0，没有 ERROR；不等同于 Mac 二进制执行。

复用项目本地模板缓存与既有 preset/脚本；仅适配新入口、资产依赖和回归入口，未绕过检查、未重新下载模板。旧白盒包及本轮中间包均保存在 history。完整日志和实际包验证字段见本轮 `run.json`、`validation.json`。

## 验收边界

| 项目 | 状态 |
| --- | --- |
| 执行者生产自测 / 包自测 | pass，以上述本轮证据为准 |
| 执行者隐藏运行画面自查 | 已实际查看并修复，提交审查 |
| 决策者验收 | pass，已实际查看11张图、独立复跑33项生产检查、复验新包及实际PCK隔离加载；见最终验收报告 |
| Controller 独立测试 | tests=[]，未运行，不能冒充决策者验收 |
| 可见 GUI / 用户桌面交互 | deferred_by_work_mode，未执行 |
| Mac 实机 / Apple 原生 codesign 验证 | pending_user_playtest |
| 真人输入、手感、难度、晕动舒适性 | pending_user_playtest |
| Developer ID 签名 / 公证 / 正式发布 | 未执行，当前仅 ad-hoc 本地测试包 |

执行者自测不等于决策者或用户通过。本轮决策者已独立完成复审，结论和证据见 [最终开发验收](ART_DEMO_DECISION_ACCEPTANCE.md)。前轮返修审查记录保留；当前开发验收通过，停在用户试玩边界。
