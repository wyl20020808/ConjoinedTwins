# 连续旅程失败与救援表现恢复

## 原因与范围

新版 `journey_view.gd` 覆盖道路场景的角色与镜头更新，只同步了救援和死亡的位置，没有接入受击到死亡、坠落翻滚、拉绳攀爬及动态机位。失败面板又立即显示，遮挡了原有失败演出。角色资源和物理救援流程仍然存在。

本任务从 `test` 的 `aa6acb9` 建立 `fix/journey-failure-presentation`，并带入当前会话已经完成的本地性能修复。没有修改原工作区、合并、推送或停止用户进程。

## 已恢复

- 撞击时播放 HitRecieve，结束后由既有 AnimationPlayer 回调进入 Death，刷新不会覆盖淘汰动作。
- 坠落位置仍来自固定步物理；恢复翻滚、隐藏地面阴影、腰部旋转与绳扣显示。
- 两名角色均可担任救援者或坠落者；恢复 RopePull、Climb、翻上路面后半段的 Run，以及面对面朝向和连按反馈。
- 救援和死亡恢复旧版机位；正常机位按旅程世界进度计算，结束后平滑回位，暂停冻结镜头和骨骼动画。
- 失败面板延后至撞击 1.6 秒或坠落 2.6 秒演出结束；重试判断采用模拟死亡时间，避免联机依赖各客户端渲染计时。
- 救援、淘汰及暂停救援时隐藏枪械；残留换弹骨骼覆盖不会压住拉绳或攀爬动作。

## 验证

引擎：本机 Godot 4.7.1；验证均为 headless。

- `tests/journey_failure_presentation.gd`：34 项检查，0 失败。覆盖真实旅程场景的动作选择和切换、失败面板、镜头变换、物理腰部挂点、两种救援角色、暂停、爬上和重试。
- `tests/journey_combat.gd`：71 项检查，0 失败。
- `git diff --check`：通过。
- 日志：`D:/ConjoinedTwins-task-temp/journey-failure-presentation-test.log`、`journey-failure-combat.log`。

启动性能探针对照：本轮修复版模拟平均 15.20 ms、每画面刷新 4.24 ms；紧接着测量的前一性能修复版分别为 15.07 ms、4.13 ms。180 个画面循环分别执行 526、523 个物理回调，均存在补帧。本轮没有观察到明显新增性能开销，但不能重复引用此前 181 回调的单次结果宣称当前环境稳定流畅，也不能把 headless 数据当作 GPU 帧率。日志分别为 `journey-failure-performance.log` 和 `journey-failure-performance-control.log`。探针退出仍有 ObjectDB 资源告警，前一版本同样存在。

真实画面、设备输入和用户试玩尚未验收；Controller 独立测试未运行。

## 试玩

双击本工作区 `试玩连续旅程.cmd`。脚本按自身目录启动新版连续旅程；之前位于 `remote-sync-20261016` 或 `local-frame-stutter` 的入口不会自动切换到本次修复。源代码尚未提交或合并到 `test`。
