# 双电脑原生联机恢复与显示平滑

任务分支：`fix/native-online-recovery`，从最新本地 `test` 的 `7c809ec60866a7eb4db1c57ab13d25942163955b` 创建。开工时已抓取远端，本地 test 领先 origin/test 4 个提交、落后 0 个提交。用户原工作区的开场动画改动未参与本轮。

## 行为变化

继续使用中继统一输入、两端确定性模拟的帧同步架构，不引入预测、回滚、状态瞬移或新的在线服务。

- **断流恢复**：UDP 连续 500 ms 没有新帧且缺帧/队列见底时主动请求补发，请求间隔至少 250 ms；请求携带已经应用的帧数。中继每 500 ms 通知最新帧号，即使领先最慢端 90 帧而停止出帧也继续通知。客户端与中继不再互相等待。超出历史窗口时明确结束并提示重新联机。
- **短按跳跃**：UDP 上行从 6 字节改为 8 字节，增加 16 位累计按下次数。按下包丢失后，松开包仍带累计次数；接收端去重并恢复按下边沿。连续丢失多个短按时在共同帧中交替输出按下/松开；长按保持原行为。序号支持回绕，待恢复事件有 32 次上限。WebSocket 仍沿用可靠输入和短按锁存。
- **版本握手**：协议从 7 升为 8。客户端和中继双向校验协议、运行脚本指纹和引擎提交版本，双方验证完成后才开始对局。未完成握手的连接在 6 秒后被清理。旧协议、不同脚本或不同引擎版本在入房阶段被拒绝。
- **显示平滑**：仅正常联机运行时，对角色、影子和整条绳的位置共同插值。目标静止后最多两个网络帧到达，不做外推；状态切换、重试、绳拓扑变化或超过 2 米的大位移直接重置。中间渲染帧只更新这部分显示，不重复同步整个场景。模拟位置、碰撞和状态指纹不变。机关、敌人及子弹尚未增加统一显示时间轴，真实画面仍需双机试玩。
- **诊断**：界面显示当前传输路径；本机和中继日志增加服务器帧数、已应用帧数、缺失帧数、补发次数、无进展时间、场景准备等待次数、模拟平均/峰值耗时和变速计数。按 10 秒窗口记录，保留原有 RTT、抖动、FPS 和卡顿统计。

## 指纹与打包

`build-tools/network_manifest.py` 对 `scripts/` 下全部运行 GDScript（不含生成清单自身）生成 SHA-256，统一 CRLF/LF。覆盖范围保守：仅改显示脚本也会要求双方更新，但只改贴图、模型和音频不会改变脚本指纹。

源码运行实时计算；导出包和只复制中继脚本的部署目录使用 `scripts/net_manifest.gd` 中的值。Windows、Web、macOS 现有打包入口在导入/导出前自动刷新清单，不改变模板缓存、签名和打包步骤。现有 Mac 中继发布工具会一起复制身份校验和清单依赖。本轮只修改发布工具，没有执行发布。

手工通过 Godot 编辑器导出前，先运行：

```sh
python3 build-tools/network_manifest.py
python3 build-tools/network_manifest.py --check
```

**升级时必须同时更新中继和双方游戏包。** 协议 7 与 8 不互通，旧客户端会明确收到版本不一致提示。本轮未生成 EXE、未部署中继、未改现有公网服务。

## 检查入口

```sh
Godot --headless --path . --script res://tests/online_recovery.gd
Godot --headless --path . --script res://tests/net_protocol.gd
Godot --headless --path . --script res://tests/online_presentation.gd
Godot --headless --path . --script res://tests/journey_online.gd
Godot --headless --path . --script res://tests/journey_combat_online.gd
python3 build-tools/check_journey_performance.py --godot /path/to/Godot --output /outside/project/evidence
```

`journey_online` 和 `journey_combat_online` 默认使用两个 UDP 客户端；`ONLINE_TRANSPORT=ws` 改为两个 WebSocket，`ONLINE_TRANSPORT=mixed` 为各一个。夹具按先后顺序确认玩家编号，避免误把先完成握手的一端当成指定角色。三项生产联机测试在场景销毁后等待 0.2 秒让 AudioServer 完成异步释放，沿用项目现有生命周期测试的收尾方式，没有删除断言或忽略泄漏。

`online_recovery` 使用真实本机中继和两个 UDP 客户端，注入整段下行丢失以及短按上行丢失，检查恢复进展、帧连续性、两端输入一致、跳跃不重不漏和双向版本拒绝。它不占用公网房间。

## 验证证据与边界

引擎：Godot 4.7.1.stable.official.a13da4feb，macOS headless。证据保存在工程外 `/tmp/conjoinedtwins-native-online-fix/`。性能报告逐文件绑定源码 SHA-256。

最终结果如下。原始失败日志保留，不覆盖为通过。执行者自测与本轮源码审查由当前会话完成，Controller 独立测试 `tests=[]`。两台 Windows EXE、公网弱网、真实键鼠/手柄、GPU 帧时间及显示插值手感未验收，`deferred_by_work_mode`。没有新提交到 test/dev/main，没有推送或发布。

### 最终自测结果

| 检查 | 结果 |
| --- | --- |
| 连续旅程性能门槛 | 27/27 通过；检查期间源码未变，退出码 0，无引擎错误或泄漏告警 |
| 断流恢复与真实双 UDP 弱网夹具 | 14/14 通过 |
| 协议拒绝、脚本指纹、长按、旧包和序号回绕 | 7/7 通过 |
| 显示插值、拓扑/状态重置及无外推 | 8/8 通过 |
| 生产旅程双 UDP / 混合传输 | 分别 13/13 通过，两端连续共同帧状态指纹一致，显示处理不改变模拟 |
| 生产战斗双 UDP | 20/20 通过 |
| 联机选章与共同就绪 | 12/12 通过 |
| 原有地址、UDP 冗余、抖动夹具 | 分别 16/16、4/4、4/4 通过 |
| 指纹辅助检查 | Python/Godot 一致、CRLF/LF 一致、脚本变更改变指纹、仅中继目录的清单回退通过 |
| Python 打包入口语法与 diff 空白检查 | 通过 |

最终七组联机检查合计 87 条断言全部通过，退出码均为 0，没有脚本/引擎错误或泄漏告警。原有三组轻量网络夹具另外 24 条断言通过。源码性能门槛结果为 `performance/summary.json`，最终联机记录为 `final-checks/summary.json`。

### 保留的基线失败

未修改的 `tests/online_backlog_catchup.gd` 仍有三条失败：两秒停顿得到 89 帧而夹具要求至少 90 帧；六秒内未缩到最多 3 帧；未达到四秒内恢复要求。在相同机器的原始 `test`（7c809ec）上，三项同样失败。旧夹具硬编码的队列数与当前自适应缓冲及慢端上限不一致，但本轮没有放宽这些断言，仍按失败记录。它不能作为生产弱网追帧延迟已经达标的证据，后续需结合两台 EXE 的实测单独处理。

原始生产联机夹具退出时的音频泄漏也在基线复现：详细对象为 WAV/OGG/MP3 播放对象。加入既有生命周期测试使用的异步音频收尾等待后，最终生产联机检查没有泄漏告警。没有通过过滤或忽略错误来接受测试。
