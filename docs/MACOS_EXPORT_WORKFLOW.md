# macOS 可重复导出流程

适用范围：ConjoinedTwins 项目后续 macOS 本地测试包导出、打包环境迁移和相关维护。由项目根目录 `AGENTS.md` 引用。

## 1. 默认原则

首次打包已经完成模板获取、Universal 2 导出配置、临时签名、资源过滤、包检查和回归脚本的准备。后续版本应复用这些工具，不重复搭建流程。

只要引擎版本未变、缓存完整且未加入需要平台适配的原生依赖，修改游戏后通常只需运行打包入口。缓存命中时模板校验不访问网络，可离线打包。缓存不随最终游戏 ZIP 分发；新电脑或不带缓存的项目副本仍需复制经校验的缓存或重新初始化。

## 2. 已固定的工具与文件

- 项目根目录：`D:/ConjoinedTwins`。
- Python：3.11 或更新版本。
- 当前引擎：`4.7.1.stable.official.a13da4feb`。
- Windows 控制台引擎：`D:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe`。
- 导出 preset：`export_presets.cfg` 中的 `macOS Universal`。
- 打包入口：`build-tools/package_macos.py`。
- 官方范围下载工具：`build-tools/official_range.py`。
- 包检查工具：`build-tools/verify_macos.py`。
- 项目本地模板：`build-tools/cache/macos.zip`。
- 模板来源与版本记录：`build-tools/cache/template-source.json`、`version.txt`。
- 下载范围缓存与响应证据：`build-tools/cache/official-ranges/`。

模板通过 preset 的 `custom_template/debug` 和 `custom_template/release` 引用；不需要安装到用户的全局 Godot 模板目录。保留已有缓存、来源记录和历史文件，不因重复导出清空它们。

## 3. 日常导出

在项目根目录执行（Agent 使用 RTK 代理）：

```powershell
rtk proxy python build-tools/package_macos.py
```

用户手动运行的等价命令：

```powershell
python build-tools/package_macos.py
```

脚本定位自身所在项目，不需要重新创建 preset。它依次进行：

1. 校验本地模板版本、SHA-256 和模板 ZIP 完整性。
2. 校验引擎精确版本，保留同名旧包。
3. headless 导入并以 release 模式导出 macOS Universal ZIP。
4. 检查 ZIP、应用结构、双架构、执行权限、实际临时签名与资源封印。
5. 从实际 ZIP 提取 PCK，在隔离资源目录用 Windows headless 引擎加载。
6. 依次运行 `PRODUCTION_TESTS` 中的当前有限三关生产回归：`baseline_controls`、`baseline_rope_view`、`road_charge_gate`、`road_sync_plates`、`endless_collision`（文件名为历史命名）和 `baseline_random_routes`（三难度合法键盘路线，约 5 分钟）。任一退出码非零、日志出现 `FAIL` 或 `SCRIPT ERROR` 即判失败；保存各测试日志、退出码、包大小和 SHA-256。历史 `endless_headless.gd` 仍断言无限无终点，已不作为打包门槛。旧 `road_headless.gd`、白盒与固定路线断言保留为历史入口，不代替新玩法验证。当前版本为 0.3.0，包检查同时要求新生产依赖 `scripts/road_templates`。

该入口是普通导出与有界验证，不是重型源码编译。遵守实时 work/idle 策略，不为检查自动启动游戏窗口。

## 4. 产物与成功判定

- 当前包：`builds/macos/ConjoinedTwins-macOS-universal.zip`。
- 同名旧包备份：`builds/macos/history/`。
- 每轮证据：`builds/macos/evidence-<UTC时间戳>/`。
- 汇总：该轮的 `run.json`，包含命令、退出码、`self_test`、包大小和 SHA-256。
- 详细日志：`import.log`、`export.log`、`validation.log`、`exported-pck-smoke.log`、`headless.log` 等。

只有本轮命令退出码为 0、`run.json` 的 `self_test` 为 `pass`，并且包路径、大小和 SHA-256 对应本轮实际产物，才报告打包自测通过。ZIP 文件存在不代表本轮成功：失败导出可能留下文件，旧包也可能仍在原路径。

不要把历史报告中的包哈希、断言数量或审查结论复制为新版本结果。需要决策者审查时由相应流程复验并记录；打包脚本本身不会自动给予决策者或用户验收。

## 5. 缓存缺失与有界恢复

先检查缓存和来源记录，不无故下载完整模板合集。需要初始化或续传时，在项目根目录运行：

```powershell
rtk proxy python build-tools/package_macos.py --templates-only --download-seconds 40
```

- 退出码 0：模板已准备完成；之后运行日常打包入口。
- 退出码 3：到达下载检查点，模板尚未完成。允许重复同一命令，从已有范围缓存续传；不能报告打包成功。
- 其他非零退出码：检查实际错误与日志，再在原工作目录恢复。

下载错误记录见 `build-tools/cache/package-error.log`，HTTP 记录见 `official-ranges/responses.json`。缓存身份或哈希不匹配时停止使用该缓存，保留现场并排查；不要关闭校验、换成未知来源模板或静默覆盖冲突文件。

仅使用匹配版本的 Godot 官方发布资产。当前脚本通过 HTTP Range 获取官方合集中的 macOS 和版本条目，记录状态、Content-Range、来源、缓存哈希与条目 CRC。只取得部分归档时不能声称已验证整个 TPZ 的官方 SHA-256；本地模板 SHA-256、条目 CRC 和完整归档官方 SHA-256 是不同证据。

## 6. 导出配置与包边界

- Windows 导出 `.zip`，保留 `.app` 内主程序的 Unix 执行权限；不要用 Windows 文件复制后的裸 `.app` 替代该 ZIP。
- 架构为 `universal`，包含 x86_64 与 arm64。
- 当前 preset 最低系统版本：Intel macOS 11，Apple Silicon macOS 13。修改要求前核对实际模板兼容性；不得只降低声明就声称支持旧系统。
- 签名使用 `codesign/codesign=1`（Built-in ad-hoc），`notarization/notarization=0`。这是本地测试包，未进行 Apple Developer ID 签名或公证。
- 保留 ARM 导出所需的 ETC2/ASTC 导入配置。导出前由脚本完成资源导入，不通过忽略配置错误强行发包。
- 包内只包含运行资源；排除 tests、docs、build-tools、缓存、历史日志、Windows 启动脚本与递归 builds。
- 新增资源后核对其进入运行包；加入 GDExtension 或其他原生依赖后必须检查 macOS 双架构二进制、加载路径和签名，不能沿用旧包结论。

## 7. 需要额外准备的情况

- **升级 Godot：** 当前下载版本、模板身份、引擎校验和 preset 均固定在 4.7.1。必须一起更新并重新验证，不仅用 `--engine` 指向另一个版本。
- **同版本引擎路径变化：** 可用 `--engine` 指向新的控制台路径，但精确版本仍须满足脚本校验。
- **迁移电脑或缓存丢失：** 恢复项目本地模板及来源记录，或按第五节初始化；核对 Python 与引擎路径。
- **原生插件、架构或最低系统版本变化：** 重新检查依赖和兼容性。
- **正式分发、公证或商店提交：** 在用户明确授权范围内另行配置证书与流程；不把当前临时签名测试包描述为已公证的发行版。

## 8. Mac 实机测试与报告

将 ZIP 传到 Mac，使用 Finder 解压，再打开 `共生连线 · 归航 Demo.app`。默认生产入口为 `scenes/road_demo.tscn`，包检查已适配机甲、工业 GLB 与共享贴图；旧白盒只保留为项目内历史调试入口。操作、Gatekeeper 指引和仅针对该应用的诊断命令见 [Mac 测试说明](MAC_TEST.md)。不得为测试关闭系统 Gatekeeper。

Windows 包结构、签名哈希和 headless 检查通过，均不等于 Mac 二进制运行、Apple 原生 codesign 验证、图形兼容性、中文显示或手感通过。没有新的实机证据时，这些项目保持待测。Controller 独立测试是否执行也应单独记录，不能把脚本自测当作 Controller 验收。

交付报告提供本轮 ZIP 路径、版本/系统要求、大小、SHA-256、实际检查结果及待 Mac 试玩事项。既有历史记录见 [首次打包报告](MAC_PACKAGE_REPORT.md) 和 [首次打包决策审查](MAC_DECISION_REVIEW.md)，仅用于追溯。
