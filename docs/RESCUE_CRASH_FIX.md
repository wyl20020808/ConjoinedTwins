# 开局救援闪退调查

当前状态：原生崩溃尚未完成修复验收。保留全部失败证据，不将中间短测通过视为解决。

任务分支为 `fix/rescue-transition-crash`，基于 `test` 的 `aa6acb9` 新建独立工作区 `D:/ConjoinedTwins-task-temp/rescue-transition-crash`，逐文件承接上一任务的 66 个未提交改动。未提交、未合并、未推送；原工作区及用户游戏进程保留。

## 已确认

- 用户三次 Windows 原生故障均为 `0xc0000005`，故障偏移 `0x13e516c`。本轮已多次复现同一偏移。
- 官方二进制反汇编与同版本源码对应到 GLES3 深度预通道读取 `GeometryInstanceSurface.owner.instance_count`。抓取的内存中存在无效表面指针；不能归因于显卡性能或内存容量不足。
- 数据断点表明排序会把已经损坏的指针移到列表首位；排序入口检查进一步确认，坏指针在排序之前已经进入列表。精确的最初损坏者仍未确认。
- 官方引擎 ZIP 的 SHA256 与 GitHub 发布摘要一致，两个已安装 EXE 与 ZIP 内容一致，没有本地文件损坏证据。
- 救援返回时原先会执行整局画面重置，销毁同局拾取物；已修正此状态切换。绳索原先每帧重建表面，现已改为固定容量索引网格、更新缓冲区，并检查非有限坐标与退化法线。

## 对照结果

证据统一保存在工程外 `D:/ConjoinedTwins-task-temp/rescue-crash-evidence`。

| 证据目录或文件 | 结果 |
| --- | --- |
| `original-user-logs/`、`windows-crashes.json` | 原始用户故障；系统原有转储原位保留 |
| `rescue-headless-before-regression.log` | 旧代码的拾取物生命周期与网格重建回归失败，修补后通过 |
| `delivery-headless-gate/summary.json` | 当时源码的 17 组回归通过；不是最终候选配置的验收 |
| `native-fixed/` | 只修状态切换和绳索，仍原生崩溃 |
| `native-angle-serial-cull/` | 串行剔除 16 轮通过，但后续更长测试推翻完整修复结论 |
| `final-native-soak/` | 128 轮无崩溃，退出泄漏 5 个对象，严格判失败 |
| `delivery-native-soak/` | 第 22 轮同地址崩溃，串行剔除加单个后台根请求仍失败 |
| `debug-native-memory.json`、`watch-invalid-write.json`、`sort-entry-invalid.json` | 无效指针、排序传播与排序前损坏的调试证据 |
| `watch-fill2-process.log` | 诊断插桩进程 128 轮未崩溃，但退出泄漏；不作为生产修复验收 |
| `native-main-load/` | 主线程资源加载、默认剔除，第 42 轮同地址崩溃 |
| `native-main-load-opengl/` | 主线程资源加载、原生 OpenGL，仍原生崩溃 |
| `native-main-load-vulkan/` | 出现空粒子实例错误，提前停止自己创建的测试进程，判失败 |
| `native-windows-main-thread/` | 资源加载、区块规划和场景剔除全部串行，仍同地址原生崩溃 |
| `native-forward-plus/` | Forward+ Vulkan 仍出现空粒子实例错误，提前停止自己的测试进程，判失败 |
| `diagnostic-no-animation-summary.json` | 禁用 AnimationMixer 的诊断仍同类原生崩溃；生产动画未禁用 |
| `diagnostic-system-font-summary.json` | 全串行配置下临时换系统字体的 32 轮短测通过；未更换生产字体 |
| `diagnostic-system-font-default-summary.json` | 恢复正常并行配置后，换系统字体仍发生原生崩溃；字体替换不能作为修复 |
| `final-review-headless/summary.json` | 撤回无效配置后的最终 17 组检查通过，附源码哈希；原生闪退仍未解决 |

已撤回无效的 Windows 全串行配置，恢复上一轮的后台加载、并行区块规划与默认场景剔除，避免无收益的性能退化。保留救援状态切换与绳索表面复用修正、回归入口及全部失败证据。候选入口为 `救援问题调查候选.cmd`，仍可能闪退，不作为修复版交付。

## 验证边界

原生回归加载真实生产场景，覆盖开局 5 米与 30 米、01/02、左右崖边、快慢救援、重试及恢复射击。夹具直接注入生产输入采样口并调用固定步，不代表真实键盘或玩家通关。截图只用于检查救援与返回镜头。

`build-tools/check_journey_performance.py` 串行执行 17 组 headless 回归；`build-tools/check_rescue_native.py` 记录原生驱动、源码哈希、退出码、错误、资源与帧间隔。引擎错误、泄漏、崩溃或源码变化均不能判通过。

独立审查 Agent、Controller 独立测试未运行；用户试玩未验收。诊断器只操作自己创建的测试进程内存，不修改已安装引擎或用户进程，也不会进入交付运行路径。

## 官方参考

- [同版本 GLES3 渲染实现](https://github.com/godotengine/godot/blob/4.7.1-stable/drivers/gles3/rasterizer_scene_gles3.cpp)
- [场景剔除线程阈值](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-spatial-indexer-threaded-cull-minimum-instances)
- [网格缓冲区更新 API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-mesh-surface-update-vertex-region)
- [上游 LoadToken 泄漏报告](https://github.com/godotengine/godot/issues/120661)：症状参考，未证明本机所有泄漏均为此类型。

官方资料用于确认实现语义；本机故障与修补效果以本轮原始证据为准。

## 限时交付结论

半小时期限内未彻底解决原生闪退。最终源码收据见工程外 `FINAL_RECEIPT.json`，原生验收维持失败；没有提交或合入 `test`，没有更换用户正在运行的版本。后续必须先定位无效表面指针最初写入者，再用原生长回归确认，不能用短测通过宣布修复。
