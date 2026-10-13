# 0.3.0 本地双人无限道路：决策者交付验收

2026-10-12，任务 t04：通过开发及本地包验收，保留真人试玩与 Mac 实机边界。沿用本 Run，未重复导出、改动 ZIP 或处理证书/网络设置。

## 本轮检查范围

读取实时交互策略，当前为 idle；仍遵守任务要求，不打开游戏窗口、不操作用户桌面。沿用已加载技能；GDScript 语言服务此前不可用，本轮采用聚焦源码读取及恢复 ZIP 对比。

核对 `delivery-baseline.zip` 中生产显示、打包脚本和 preset 与现有文件的差异：生产代码改动为补齐双人教学、删除不可达的固定终点完成文案；打包入口改用当前无限场景与碰撞回归，检查增加 0.3.0 和 road_templates 依赖。既有签名、封印、资源过滤检查保留。原测试、旧报告和恢复包仍存在；非 Git 项目只完成上述聚焦核对，不宣称核验了全项目变更。

## 独立实际包验证

在项目根目录执行 `rtk proxy python tests/decision_delivery_review.py`，最终退出码 0。未运行 `package_macos.py`，未重新生成 ZIP；独立证据写入 `builds/macos/decision-review-t04-20261012/`。

1. 复用已审读的 `verify_macos.py` 对现有 ZIP 独立复查，退出码 0：ZIP CRC、Unix 执行权限、x86_64/arm64 两架构、两架构全部签名代码页及特殊槽 1/3、3 个资源 SHA256 封印通过。PCK 全部资源 MD5 通过，生产场景、双方机甲、工业资产及生成脚本存在；排除历史、测试、制作工具等非运行资源。
2. 从当前 ZIP 重新提取实际 PCK，SHA256 `fe405d681f3d0999a7b6b8f36b617a1fe581cb3a5f86041c05bb4d90dc14b8b6`。在独立证据目录以 `--headless --main-pack actual-export.pck --script <外部检查脚本>` 运行。外部脚本保留原断言，只更换结果写入路径；加载生产规则与模型均来自 PCK，未混入源码项目资源。
3. 实际 PCK 无限生产场景 **48/48**、碰撞回归 **6/6** 通过，两命令均退出码 0。覆盖简单/普通/困难 × 种子 11、42、20261012、合法联合输入、前后错位、独立跳跃、复现、暂停及重试。最长 370 秒模拟运行累计 52282.107 地面单位（约 2614 米），10 次重定位，危险峰值 20、节点峰值 2059，实际拒绝并回退 6 个候选。结果为 `packed-endless-result.json`、`packed-collision-result.json`，详细命令、退出码和日志见 `review.json`；日志无引擎 ERROR。

首次复查脚本因 Windows Python 子进程输出采用 GBK、读取按 UTF-8 失败；保存 `review.json.attempt1` 和 `validation.log.attempt1`，设置该子进程 `PYTHONUTF8=1` 后上述复验成功。这是复查日志编码修正，未改变包、校验规则、系统环境或 TLS。

当前 ZIP 为 `builds/macos/ConjoinedTwins-macOS-universal.zip`，0.3.0，**61,188,068 字节**，SHA256 **899df5e702966f1d171be3960b2be2b97386af86291b7d30137d62532e5cca5b**，与原始 `evidence-20261012T115750573615Z/run.json` 完全一致。旧包 `history/ConjoinedTwins-20261012T115750573615Z-c1a963299525.zip` 大小 61,170,971，重新计算哈希与原记录一致；恢复 ZIP CRC 正常。

## 真实画面审查

决策者实际打开并查看本轮全部八张 1280×720 像素图：`docs/screenshots/t04-start.png`、`t04-wide-offset.png`、`t04-jump.png`、`t04-pause.png`、`t04-dynamic.png`、`t04-hit.png`、`t04-failure.png`、`t04-retry.png`。截图元数据记录种子 20261012、普通难度，保存均成功。

近景跑道宽敞、两侧边界及前后错位可读，侧景不挡主通道；开始页明确前后调节、连线及独立跳跃按键。跳跃图中 01 腾空、02 地面，阴影留地、连线端点抬高；动态地刺危险文字与暖色轮廓一致。暂停提示释放旧输入，失败页显示角色 01 和高货箱原因，重试图恢复双方分站及累计 0 米。失败夹具两人重叠是同目标输入造成的合法状态，不作为清晰分站证据。

源码与打包场景检查支持原骨骼 Run/Jump/HitRecieve_1/Death 及固定镜头设置；截图不能证明完整动画手感、真实键盘或舒适度。远景预警文字较密，实际游玩可读性继续列入真人清单。本轮未发现需返工的明显构图或 UI 问题；t03 的预警材质隔离修复仍在当前代码和包中。

## 状态与交接

执行者自测见 `LOCAL_DELIVERY_REPORT.md`，本报告为独立决策者验收。Controller tests=[]：独立测试未运行。原始打包 run.json 的 pending 是打包时状态，保留原记录；本轮最终独立结果为上述 review.json 的 pass。

可见 GUI 未验收，保留执行者 `deferred_by_work_mode` 记录。本轮所有检查为 Windows headless、静态签名哈希与已有隐藏运行截图；Mac 二进制、Apple 原生 codesign、图形兼容性、中文及两架构实机均待验收。实体键盘多键并按、启动/恢复释放按键、双人合作、难度和晕动体验见 `MAC_TEST.md` 真人清单；持续共同绕行走廊的挑战性与多样性仍待试玩调校。

三个独立检查子命令及驱动进程已退出；`rtk proxy powershell -NoProfile -File tests/decision_delivery_process_audit.ps1` 退出 0，未发现命令行关联本项目的 Godot/Python 进程。未提交、合并、推送、公开发布、部署或修改其他项目。
