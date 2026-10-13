# macOS 打包执行者自测报告

仅增加打包工具、preset、文档及 Universal 导出必需的 ETC2/ASTC 导入选项，未修改生产游戏脚本或三关配置。引擎实测为 `4.7.1.stable.official.a13da4feb`。全程 headless，无源码编译、全局模板安装、提交、推送或发布。

## 当前产物

- 路径：`builds/macos/ConjoinedTwins-macOS-universal.zip`
- 大小：60,407,517 字节（约 57.61 MiB）。
- SHA-256：`1018e49b712e080b4768c39b0a87cfb93e990a839e3975a7c93ef952a66e894a`
- 本次证据目录：`builds/macos/evidence-20261012T064347091044Z/`。
- 入口：`共生连线 · 白盒.app/Contents/MacOS/共生连线 · 白盒`。
- Bundle ID：`org.conjoinedtwins.whitebox`；版本 `0.1.0`。

重复导出会改变 ZIP 时间元数据，以对应 `run.json` 的 SHA-256 标识产物。先前调试包完整保留在 `history/`，路径、大小、校验值记录于对应 `evidence-*/run.json`。首次包漏掉 preload 依赖，已通过实际 PCK 清单发现并改用 `all_resources` 导出；历史包不作为试玩包。

## 官方模板与局部校验边界

官方发布页：https://github.com/godotengine/godot-builds/releases/tag/4.7.1-stable

实际请求资产：https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz

发布页未提供独立 macOS 模板。采用 HTTP Range 读取 ZIP 中央目录及指定条目，Python zipfile 支持 ZIP64。响应为 206，每段检查 Content-Range、资产长度、ETag 和长度，保存实际 `release-assets.githubusercontent.com` HTTPS 重定向 URL、Last-Modified 与段 SHA-256。证据位于 `build-tools/cache/official-ranges/responses.json`。原 55,574,528 字节 `.partial` 保留，未继续下载完整合集。

- 全合集长度：1,280,486,955 字节。
- 官方整包 SHA-256：`86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72`。
- **全归档官方 SHA-256 校验未执行**；仅取得选取条目，CRC 和本地 SHA-256 不等于官方整包校验。
- `templates/version.txt`：13 字节，内容 `4.7.1.stable`，CRC32 `7d1ba078` 已检查。
- `templates/macos.zip`：压缩段 122,692,691 字节，解压后 123,444,191 字节；CRC32 `9c6ff077` 已检查，内部 ZIP CRC 全部通过。
- 本地 macos.zip SHA-256：`f9de131f5ed0210924b9b156aea43b1e20fd720dd97690e151081a65c0937a3e`。

版本及边界记录于 `template-source.json`，本次证据目录保存副本。仅使用项目 custom_template 路径，未覆盖既有工具配置。

## 验证结果

`run.json` 保存命令和退出码；import、export、静态验证、headless 回归均退出 0。`export.log` 保存 Built-in 签名过程，`validation.json` 保存实际结构与资源清单。

- ZIP CRC 全部通过，Info.plist 入口和合法 bundle id 与 preset 一致。
- Mach-O 包含 x86_64 与 arm64，主程序 ZIP Unix 模式为 `100755`。
- 两个架构均有 LC_CODE_SIGNATURE / SuperBlob / CodeDirectory，flags `65538` 含 CS_ADHOC。SHA-256、SHA-1 目录分别校验全部代码页（x86_64 21,098 页、arm64 20,059 页），同时检查 Info.plist 和 CodeResources 特殊槽绑定。
- CodeResources 中 3 个 SHA-256 资源封印通过。PCK 所有资源 MD5 通过，包含主场景、六个生产脚本、必要 remap 和 Godot 元数据；无 tests、docs、缓存、历史日志、Windows 启动脚本或递归 builds。
- 真实场景回归 PASS：65 项检查、6,012 帧、无失败，最大中心距离 `220.000030517578`（既有浮点容差内），见 `headless-result.json`。
- 从最终 ZIP 提取的 PCK 在隔离资源路径下由 Windows Godot headless 加载主场景并运行 3 帧，退出 0、日志无 ERROR；见 `exported-pck-smoke.log`。这是实际导出资源加载验证，不是 Mac 二进制启动测试。
- 中文使用 Godot 默认字体和 macOS 系统回退，实际显示待实机确认。

上述为 **执行者自测**，Windows 静态签名哈希检查不等于 Apple codesign 实机验证。Built-in ad-hoc，notarization 禁用，未公证；Mac 实机启动与试玩 pending。执行者提交时决策者独立审查 pending；其后已由决策者独立复验通过，见 [macOS 决策者审查](MAC_DECISION_REVIEW.md)。Controller 独立测试未运行（tests=[]）。

工作策略文件、caveman 技能读取被工具路径权限拒绝，未绕过；按未知策略默认 work。无可调用 Serena，使用聚焦读取和内容搜索。未进行桌面或用户浏览器操作，GUI 验收为 `deferred_by_work_mode`，未宣称 Mac 实机 PASS。
