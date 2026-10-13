# macOS 测试包决策者审查

任务：`t01-macos-test-package`，Run：`39e22646-971d-4d9b-ab42-0dec51a630e4`。

结论：本次 Windows 打包、静态检查和 headless 验证范围内 **PASS**。Mac 实机启动、图形兼容性、中文显示和试玩仍为 **pending**；未进行 Apple 原生 codesign 实机验证，未公证。Controller 独立测试未运行（tests=[]）。

审查读取了现有 preset、三个打包工具、实际 ZIP、官方 Range 缓存与 HTTP 记录、执行者日志及中文测试说明。独立证据位于 `builds/macos/decision-review-39e22646/`，汇总为 `review.json`。

- 核对 38 段 HTTP 206 记录、Content-Range、长度、相同 ETag、官方 HTTPS URL 与 `release-assets.githubusercontent.com` 重定向，验证各段缓存 SHA-256。利用缓存中央目录和压缩段离线重建 version.txt、macos.zip；长度、CRC、本地 SHA-256、版本和模板内部 ZIP 完整性均通过。没有新下载；全归档官方 SHA-256 校验未执行。
- 原 55,574,528 字节 `.partial` 保留。核对前一包 history 副本的实际 SHA-256 与记录一致。
- 复验实际 ZIP CRC、UTF-8 文件名标志、Info.plist 入口、bundle id、Unix 执行权限 `100755`、x86_64/arm64 和两种架构的 ad-hoc 签名。验证签名代码页、Info.plist/CodeResources 绑定和资源封印。
- PCK 包含主场景、全部六个生产脚本和必要 Godot 元数据，未包含 tests/docs、下载缓存、日志、Windows 脚本或 builds。直接从最终 ZIP 提取 PCK，在隔离资源路径下用指定 Windows headless 引擎运行 120 帧，退出 0、无 ERROR。这不是 Mac 二进制执行。
- 独立运行真实场景回归，65 项检查、6,012 帧通过，失败数组为空。主场景与六个生产脚本均与既有 `tests/source_hashes.json` 的历史基线哈希一致；该局部基线比较不等于全量项目变更证明。
- 中文 Mac 说明覆盖解压启动、现有操作、Gatekeeper 的“隐私与安全性 / 仍要打开”，终端命令仅检查指定 app，不关闭 Gatekeeper。

接受的成品：`builds/macos/ConjoinedTwins-macOS-universal.zip`。

大小：60,407,517 字节。SHA-256：`1018e49b712e080b4768c39b0a87cfb93e990a839e3975a7c93ef952a66e894a`。

本次决策者读取的交互策略为 idle，仍遵守任务明确要求，全程无桌面窗口操作、提交、推送或发布。未更改策略及全局工具配置。无可调用 Serena，使用聚焦 RTK 搜索与精确源码读取。所有本次复验子进程同步结束。
