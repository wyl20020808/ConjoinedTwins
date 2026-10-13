# 双人四向移动与宽道路：决策者验收

日期：2026-10-12。任务：`t01-duo-movement-wide-road`。工作目录：`D:/ConjoinedTwins`。

## 结论与范围

本任务通过。核对生产移动、输入、动画与道路显示代码，确认主入口仅本地双人；01 WASD / 空格，02 方向键 / 回车，无主玩法 AI 或低姿态动作。可玩横向边界由 ±156 扩大到 ±234 地面单位，即 1.5 倍；显示道路宽 24.6 米，侧景同步外移，镜头固定。

本任务仍为 450 米教学路线。新增障碍、无限道路、公平生成、难度和完整动作调校由后续任务实施。本轮未导出 Mac 包，旧包不代表本轮实现。

## 独立验证

使用 Godot `4.7.1.stable.official.a13da4feb`，实际执行：

```powershell
rtk proxy "D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless --path D:/ConjoinedTwins --script res://tests/decision_duo_t01_review.gd --log-file D:/ConjoinedTwins/tests/decision-duo-t01-headless.log
```

退出码为 0，46 项检查通过、0 项失败。结果为 `tests/decision-duo-t01-result.json`；保留执行者原测试脚本及结果，不覆盖其证据。

独立复跑原 40 项生产场景检查，补充 6 项：60/120 Hz 输入分帧的一致性；12 个种子共 4320 步输入逐步检查双方边界、地面连接、非负跳跃高度和固定镜头；双方分别通过正常输入撞击生产货箱共同失败；生产受击动画转入死亡；持续横移到宽道路右边界。随机输入仅验证本任务运动约束，不是后续随机障碍生成的公平性验收。

低障碍高度检查仍为明确夹具；合成输入只进入本次 headless Godot 进程，不代表真实键盘或桌面输入验证。主路线通关使用原生产障碍及正常移动，不修改角色位置或通关状态。

## 视觉与恢复材料

实际打开查看 `docs/screenshots/duo-wide-road.png`、`duo-jump.png`、`duo-start.png`、`duo-failure.png` 的像素。四张均为 1280×720 运行截图：近处跑道宽敞，两侧边界及外移设施可读，双方轮廓和青橙识别清楚；独立跳跃的阴影留在地面，连线端点随高度变化；开始页操作与失败原因一致。截图与代码证据支持本任务基础表现，不代替实时动画手感评价。

已检查 `build-tools/duo-movement-baseline.zip`：10 个条目，ZIP CRC 无错误，含修改前生产脚本、规则、说明及两台机甲。与备份对比，两台机甲资源及导入配置保持一致。本项目为非 Git 目录，此次为指定文件核对，不能声明全量项目变更已验证。

决策者修正资产清单中仍描述静态滑行的旧说明，明确区分上轮姿势与本轮骨骼动画。修正前副本为 `build-tools/duo-review/ASSET_SOURCES.before-review.md`。其余生产代码未由本次审查修改。

## 验收边界

- 执行者自测：原 40 项检查及隐藏运行截图，见 `DUO_MOVEMENT_REPORT.md`。
- 决策者审查：本报告记录的代码、恢复包、独立 46 项检查及截图审查通过。
- Controller 独立测试：未运行，配置为 `tests=[]`。
- 可见 GUI 验收：执行者按无法读取实时策略时的 work 默认规则记录 `deferred_by_work_mode`；本次审查仅查看已有图片并执行 headless 检查，没有桌面交互。
- 真实键盘多键并按、双人合作手感、实时动画及晕动体验：待用户试玩。
- Mac 导出和 Mac 实机：本任务未运行。

本次无提交、合并、推送、公开发布或后台写入进程。后续任务应沿用当前 Run 和执行会话。
