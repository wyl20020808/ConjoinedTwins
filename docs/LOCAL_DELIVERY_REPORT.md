# 0.3.0 本地双人无限道路：执行者交付报告

任务 t04；保留最新 WASD/方向键四向移动、空格/回车独立跳跃与宽道路方向。t01–t03 决策者验收状态依据本次 Controller 派发反馈；本报告不代替 t04 独立验收。

## 实际改动与恢复

开始页补齐前后活动范围、连接上限、按键释放和危险应对教学；删除不可达的旧固定终点完成文案。固定镜头和 24.6 米宽路面保持，原机甲骨骼 Run/Jump/HitRecieve_1/Death 继续使用。Mac preset 更新为 0.3.0，复用原缓存与导出入口；包检查增加版本及 road_templates 依赖，生产测试切换到无限入口和碰撞回归，未绕过签名或资源检查。同步 README、Mac 操作、资产来源及导出流程。

修改前恢复包 `build-tools/delivery-baseline.zip`；原测试、历史报告、截图及旧包保留。旧 AI/固定路线断言的重试布局和终点假设不适用于新生成生命周期，文件未删除或改成较弱断言；历史 65/40/50 项不计入本轮结果。

## 交互策略与恢复边界

本轮执行前尝试读取实时策略被工具权限拒绝，按项目规则采用 work，不绕过读取限制。仅普通 headless、局部导出及已有任务独占隐藏宿主，无用户输入、焦点、浏览器或可见窗口操作。可见 GUI 记录 deferred_by_work_mode。

打包已完成后，执行服务发生 UnknownError: unknown certificate verification error。依据 Controller 核实的终态反馈恢复本次剩余证据核对和文档；没有重复打包，没有关闭 TLS 验证或修改网络、认证、系统配置。续接只读核对包身份及日志，首次 Python 读取因系统 GBK 默认编码失败，显式 UTF-8 后成功；不影响原包。

## 实际命令与验证

工作目录 D:/ConjoinedTwins；Godot 4.7.1.stable.official.a13da4feb。

1. `rtk proxy python build-tools/capture_hidden.py res://tests/capture_delivery.gd`：退出 0。生产场景、种子 20261012、普通难度，普通输入与固定步，不瞬移；截图八张，记录 `docs/screenshots/t04-capture.json`，日志 `tests/delivery-capture.log`。
2. `rtk proxy python build-tools/package_macos.py`：退出 0，命中已校验项目本地模板缓存，未重新下载。详细所有子命令、退出码与日志路径见证据目录 run.json。
3. 打包内 headless 导入、release 导出、verify_macos、隔离目录 --main-pack 实际 PCK 加载均退出 0；无限生产验证 48/48、碰撞回归 6/6，相关日志无 ERROR。
4. 恢复后重新计算现有 ZIP 大小和 SHA256，与 run.json 一致。检查 validation.json 为 pass，架构 x86_64/arm64、签名页及特殊槽和 3 个资源封印通过；未重复导出。

无限验证为三种难度 × 种子 11、42、20261012，含前后错位、独立跳跃、复现、跨段、暂停和资源池。最长有界运行 370 秒模拟约 2614 米，10 次重定位，危险峰值 20、节点峰值 2059。碰撞专项包含明确夹具的双方动态刺高合法通过及高速飞行物命中；脚本输入不代表物理键盘能力。

## 本轮实际包身份

- 包：`builds/macos/ConjoinedTwins-macOS-universal.zip`
- 应用版本：0.3.0；Universal 2；Intel macOS 11、Apple Silicon macOS 13。
- 大小：61,188,068 字节。
- SHA256：`899df5e702966f1d171be3960b2be2b97386af86291b7d30137d62532e5cca5b`
- 原始打包证据：`builds/macos/evidence-20261012T115750573615Z/`，run.json self_test=pass，打包时 decision_review=pending、mac_playtest=pending。原记录保留，最终独立状态见 [决策者交付验收](LOCAL_DELIVERY_DECISION_REVIEW.md)。
- 历史旧包：`builds/macos/history/ConjoinedTwins-20261012T115750573615Z-c1a963299525.zip`，61,170,971 字节，SHA256 `c1a963299525134808af01a944f056c6728545b63bc968a8800938b7a4d97711`。

这是本地 ad-hoc 测试包，未公证。Windows 签名哈希与封印检查不等于 Apple 原生 codesign 或 Mac 二进制实机运行。实际 PCK 在 Windows headless 隔离加载，不冒称 Mac 执行。

## 真实画面自查

八张 `t04-*`：start、wide-offset、jump、pause、dynamic、hit、failure、retry。执行者已实际查看开始、前后错位、跳跃、动态刺与扫描束、暂停及失败画面。跑道占据近景下方、道路消失点固定；边界与双方前后位置可读，侧景未遮住主通道；01 腾空、02 地面，阴影留地，连线端点抬高；动态危险文字与尖刺轮廓可辨；开始与暂停操作提示、失败角色/原因可读。失败测试两人同一横向目标导致角色重叠，是可允许的逻辑状态，不当作双人清晰分站展示。短截图不能证明动画手感或晕动舒适度。

本次修正旧固定终点文案并补教学信息；未发现需改变已定镜头的明显构图问题。决策者必须独立实际查看上述本轮截图后记录结论，执行者不替代该项。

## 验收与真人清单

- 执行者：以上自测完成。
- 决策者：t04 包、代码及八张真实截图独立审查通过；实际 ZIP 提取 PCK 的 48/48 与 6/6 检查通过，详见 [独立验收报告](LOCAL_DELIVERY_DECISION_REVIEW.md)。
- Controller：tests=[]，独立测试未运行。
- 可见 GUI：deferred_by_work_mode。
- 真人：同键盘双方同时四向移动及独立跳跃是否丢键；启动/暂停/重试释放按键体验；前后错位、连接限制和协作手感；三难度反应窗口和挑战性；预警/落地动作可读性；固定镜头晕动。
- Mac：解压启动、中文、图形、帧率、键盘布局、原生 codesign/Gatekeeper 与两架构实机待验收，见 MAC_TEST.md。

当前公平模板使用持续共同绕行走廊，不包含必须跳跃求解通路；保持既有已验收实现范围，挑战性与路线多样性仍需真人调校。所有本次工具调用为同步操作，导出与隐藏宿主子进程已经退出，未留下后台写入进程。未提交、合并、推送、公开发布或部署。
