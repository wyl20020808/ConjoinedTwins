# 本轮恢复材料与改动范围

## 当前短绳三关综合集成恢复点（t06，2026-10-13）

第二关内容返工恢复点：`build-tools/short-rope-t06/rework1/baseline.zip`，174 份返工前文件及逐文件哈希见 `rework1/baseline.json`。包含旧生成源码、目录/整关/集成测试、完整旧输入结果和初轮执行证据；原 `decision-review/` 未改动。返工仅修改生产段落选择及新增身体高度/石球布局，追加实际内容覆盖断言，重新记录多种子路线并更新工具/说明。原运动、绳索、动态威胁机制、奖励和生命周期源码保持原样。

当前哈希与完整性审计位于 `rework1/manifest.json` 和 `rework1/evidence-audit.json`。审计明确列出授权修改文件，核验两份恢复 ZIP，检查未涉及文件及初轮执行证据仍未变化；此前 t05 批准源码只作为旧基线，新生成源码待配置决策者重新验收。下列初轮恢复记录继续保留，不能将其“未修改生产源码”描述套用于本次返工。

本轮修改前恢复材料为 `build-tools/short-rope-t06/baseline.zip`，逐文件 SHA256 和大小见同目录 `baseline.json`。包含生产源码、历史测试断言、原结果及日志、README、启动验证入口、设计说明、恢复清单和资产许可文件；压缩包完整性及历史文件未变检查见 `evidence-audit.json`。t01–t05 的原备份与决策者审查材料保留，没有覆盖或删除。

本轮仅新增 t06 生产集成测试、综合执行和证据审计工具，修正验证 CMD、README、当前设计与报告。本轮没有修改生产玩法源码、历史白盒常量、已有资产或许可。旧 t02/t04 固定走廊契约的实际失败结果保存在 `executor/t02-history/` 和 `executor/t04-history/`；t06 首次预期标题写错的失败保存在 `failures/t06-initial-title/`。原测试结果在每次运行后恢复，当前结果使用独立目录。

按需恢复前先另存当前文件，再按 `baseline.json` 选择性解压；不要整包覆盖项目。新增文件清单和最终哈希见 `manifest.json`。若需要撤销新增工具，先对照清单人工选择，不删除整个目录或历史证据。目录无 Git；本轮未初始化、提交、合并、推送或发布，不含 Mac 打包。

下面保留早期美术 Demo 的原始恢复记录，其中“本轮”指其历史任务。

任务：t01-road-depth-art-demo；Run：a95c93e3-d954-4bb6-abe6-fddb96abbdf2。本轮沿用原工作目录和执行会话，未启动新的 Controller，未更改模型配置。

修改前保存了 `build-tools/art-demo/whitebox-baseline.zip`，包含 47 份文件：项目配置、导出 preset、README、启动/验证脚本、六份旧生产脚本、主场景、旧测试源码与结果/日志、历史文档及原打包 Python 工具。逐文件 SHA256 与清单见同目录 `recovery.json`。恢复时先另存当前成果，再按清单选择性解压；不要直接覆盖整项目。

旧 Mac ZIP 由现有打包入口在导出前复制至 `builds/macos/history/`。旧包原 SHA256 为 `1018e49b712e080b4768c39b0a87cfb93e990a839e3975a7c93ef952a66e894a`，本轮第一次复制为 `ConjoinedTwins-20261012T081826560041Z-1018e49b712e.zip`。更早的包与证据目录继续保留。模板缓存未重新下载、未安装到全局目录。

本轮新增 `road_run.gd`、`road_demo.gd` 和 `road_demo.tscn`，新角色/环境运行资产、资源下载及隐藏截图工具、新玩法验证、运行截图和说明。修改 `project.godot` 的默认入口及分辨率，修改 preset 和既有打包验证以准确检查新依赖，修改历史白盒启动脚本使其明确打开旧场景。`link_motion.gd` 直接复用，原六份生产脚本与旧测试断言没有改动。白盒作为历史调试入口保留，不进入新 Mac 包。

下载页、公共下载目录响应、原工业包及来源哈希保存在 `build-tools/art-demo/`，该目录不会进入运行包。一次探索误把 Drive 预览 GIF 保存为 `mech.zip` 后发现不是 ZIP；该诊断残留不参与资源导入或打包。实际角色来自公共目录的独立 glTF 文件。

本轮只修改 D:/ConjoinedTwins，没有提交、推送或发布，没有修改策略、Hook 或其他项目。

## 决策者审查返修恢复点

返修前另存 `build-tools/art-demo/pre-review-fixes.zip`，共 76 份当前生产源码、测试、截图、报告和证据文件；逐文件哈希见同名 JSON。此前决策者审查报告和独立检查证据没有覆盖。返修只改显示层屏障范围、港区远景、受影响测试与截图工具及报告；生产地面规则 `road_run.gd`、原连接代码与历史白盒没有改变。

上轮审查的 Mac 包（SHA256 `e0d0ad1f72f24939344bf2aa4c4488d47e5ee97471a66dfcade2b4bf966348f7`）已由现有打包流程复制至 `builds/macos/history/ConjoinedTwins-20261012T091835175791Z-e0d0ad1f72f2.zip`。
