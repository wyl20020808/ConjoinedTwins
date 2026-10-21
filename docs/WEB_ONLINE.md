# 网页版联机说明

2026-10-21 起网页版按章节拆包、本机缓存并使用新的启动页与联机协议 7，导出与部署变化见 [主界面、按章下载与联机优化](CHAPTER_MENU_ONLINE.md)。当前默认入口已更新为连续旅程，单人、人机和新版远程连接方式见 [连续旅程网页版更新](JOURNEY_WEB_UPDATE.md)。下文的旧自动道路验证记录仅代表历史版本。

当前公网入口：[打开游戏](https://www.u4139693.nyat.app:57412/)。原生 UDP 公网隧道目前未配置；网页通过同域名 `/ws` 联机。

适用范围：队友不装 App，用手机、平板或电脑的浏览器打开一个链接就能和你联机合作。服务器跑在你 24 小时开机的 Mac mini 上，经 SakuraFrp 暴露到公网。仅供个人试玩。

## 工作方式

- 浏览器不能收发 UDP，网页版改用 WebSocket（TCP）联机。中继服务器 `scenes/net_relay.tscn` 现在同时监听两个端口：
  - UDP 24680：原生客户端（Windows / Mac / iPhone App）用的 ENet，参数 `--port=`；
  - TCP 24681：网页版用的 WebSocket，参数 `--ws-port=`，传 `0` 表示不开。
- 两种连接进同一个房间，网页版和原生客户端可以混合联机，但见下方“已知限制”中的不同步风险。
- 网页版默认连接 `wss://<网页所在主机>/ws`，所以网页和联机由同一台 Mac mini 提供时，队友打开链接后不用填地址，直接点“联机”。网址里加 `?server=wss://其他地址` 可以改连别的服务器。

## Mac mini 上的部署结构

```
浏览器 ──https/wss──> SakuraFrp 节点（自动 HTTPS，nyat.app 子域名证书）
        ──TCP 隧道──> Mac mini 127.0.0.1:8080（Caddy）
                         ├─ /ws  → 127.0.0.1:24681（中继 WebSocket）
                         └─ 其他 → 网页静态文件（builds/web 的副本）
原生客户端 ──UDP 隧道（原有）──> Mac mini 127.0.0.1:24680（中继 ENet）
```

- Caddy 配置见 [deploy/macmini/Caddyfile](../deploy/macmini/Caddyfile)，网页根目录由环境变量 `CT_WEB_ROOT` 指定。
- SakuraFrp 需要新建一条 **TCP** 隧道：本地 `127.0.0.1:8080`，“自动 HTTPS”设为“自动”，并在管理面板“子域绑定”申请一个免费的 `nyat.app` 子域名绑定到这条隧道（重启隧道后日志出现“已从服务器为 … 加载证书”即可）。访问地址形如 `https://xxx.nyat.app:端口/`。
- 原有的 UDP 隧道保持不变，原生客户端照旧使用。

依据（SakuraFrp 官方文档，2026-10-14 查阅）：
- [自动 HTTPS](https://github.com/natfrp/wiki/blob/master/frpc/auto-https.md)：国内节点穿透网页“必须”开启自动 HTTPS；游戏的 UDP 隧道“不要”开启。
- [子域绑定](https://github.com/natfrp/wiki/blob/master/bestpractice/domain-bind.md)：免费提供 `nyat.app` 子域名和 SSL 证书，绑定到开启自动 HTTPS 的隧道后自动加载证书；该域名开启了 HSTS，必须用 https 访问。

未验证事项：
- SakuraFrp 自动 HTTPS 隧道转发 WebSocket 升级请求，文档没有专门说明。自动 HTTPS 的原理是解开 TLS 后把明文转给本地服务，WebSocket 握手本身就是 HTTP 请求，理论上可行，需要部署后实测。
- 免费隧道的限速（文档提到约 10 Mbps）下，网页首次加载几十 MB 的耗时。

## 导出网页版

在 Windows 或 Mac mini 上运行（需要 Godot 4.7.1，Python 3.9 及以上）：

```
python build-tools/prepare_web.py                                                     # Windows，默认引擎路径
python3 build-tools/prepare_web.py --engine /Applications/Godot.app/Contents/MacOS/Godot   # Mac
```

脚本先从 Godot 官方 GitHub Release 按需读取 `web_nothreads_release.zip`（约 10 MB，存到被 Git 忽略的 `build-tools/cache/`，来源记录在 `web-template-source.json`），再导出到 `builds/web/`。旧产物移到 `builds/web-history/`，日志写入 `builds/web-evidence-<时间>/`。使用无线程模板，不需要配置 COOP/COEP 响应头。

更新网页版的步骤：拉取新代码 → 重新导出 → 把 `builds/web/` 同步到 `CT_WEB_ROOT` 目录 → 重启中继（协议有变时）。两人刷新页面即可拿到新版本。

### 网页包体积（2026-10-20）

网页版会把整个 `index.pck` 下载并读进内存，PCK 体积直接决定首访等待和手机内存。用户要求压缩不能降低画面质量，因此默认只做不改变画面的处理（e74af86 的 187 MB → 约 160 MB，brotli 147 MB → 135 MB）：

- Web 预设排除确认运行时不加载的资源：未绑骨的怪物/村民原件（运行时只用 `rigged/`，原件与 rigged 各导入一份同样的贴图）、未引用的鹰与鸟模型、`Adventurer_B`、只被旧白盒 `build_road()` 使用的 DeadTree。
- 28 件嵌入贴图的 Tripo 模型关闭 `create_shadow_meshes`。shadow mesh 只是同一几何的仅位置副本，用于加速阴影绘制，关闭后阴影形状不变。

会降低画质或改变压缩格式的进一步瘦身做成可选清单，单独放在 `chore/web-pck-diet-lossy-options` 分支，每项一个提交，由用户看过对比后逐项决定是否采用。

新增或删减资源后用下面两步检查，再部署：

```
python3 build-tools/pck_report.py builds/web/index.pck                          # 体积构成
/Applications/Godot.app/Contents/MacOS/Godot --headless --main-pack builds/web/index.pck -s "$PWD/build-tools/verify_web_pack.gd"   # 资源完整性
```

`verify_web_pack.gd` 加载生产脚本常量里的全部资源路径与模型表，再按生产入口逐章、多种子扫过全程，输出 `VERIFY_WEB_PACK missing=0` 才算通过。它是桌面无头运行，不覆盖 `OS.has_feature("web")` 分支、GPU 渲染与浏览器内存，画质变化需要真机试玩确认。

## 本地自测

1. `启动联机服务器.cmd`（同时开 UDP 24680 和 WebSocket 24681）。
2. 在 `builds/web/` 目录运行 `python -m http.server 8000`，浏览器打开 `http://localhost:8000/`（localhost 属于安全上下文，可以不用 https）。
3. 地址栏留空或填 `ws://127.0.0.1:24681`，两个标签页各点“联机”。

## 网页版专属处理

- 中文字体：浏览器里的 Godot 用不了系统字体，网页版通过 `project.godot` 的 `gui/theme/custom_font.web` 加载 `assets/fonts/web_ui_font.tres`（Noto Sans SC 子集，约 1 MB，来源见 ASSET_SOURCES.md）。桌面和 iOS 不受影响。项目新增生僻字后运行 `python build-tools/make_web_font.py` 重新生成子集。
- 开始面板：网页字体行高更大、折行更多，网页版把面板行间距从 20 收到 12，保证底部联机状态行在 16:9 画面内可见。

## 已知限制

- 网页版中文自动换行只在空格处断行，个别句子会出现“100 / 秒”分行、句号单独一行的情况，不影响操作。
- 浏览器把标签页切到后台时会暂停游戏，联机的另一方也会跟着停住，切回来后追帧继续。两人各用一台设备时没有这个问题。

- 首次打开要下载引擎和游戏数据（几十 MB），之后浏览器会缓存。
- iPhone Safari 不支持真正全屏，可用“添加到主屏幕”后打开；声音要在第一次点击屏幕后才会响。
- 手机浏览器性能低于原生 App，3D 帧率需要真机确认。
- WebSocket 走 TCP，网络抖动时偶尔会整体卡顿一下，不会丢操作。
- 网页版（WebAssembly）与原生客户端混合联机时，三角函数等数学库结果可能有细微差异，存在“画面不同步”风险。建议同一局两人用同一种客户端；不同步时服务器会提示，回开始页重新联机。
- headless 回归只证明本机中继与 WebSocket 帧同步正确，不代表手机浏览器触屏、帧率和公网联机已验收。

## 无线程关卡生成修复（2026-10-14）

无线程 Web 模板不能启动 `Thread`。旧版在后台验证线程不可用时连续安装 `safe` 空段，导致独立教学门存在，但开门后的随机障碍消失。

当前 Web 使用可暂停的生产验证任务：每次轮询推进最多 32 个验证固定步，验证规则、候选顺序、散布复证、奖励和碰撞检查与原生 worker 共用实现。原生端保留后台线程；线程启动失败也转入同一分帧路径，不因能力缺失直接吞掉障碍。联机仍在原来的模拟距离边界安装段落；生产场景在应用当前帧前分帧准备证明与模型，未就绪时保留该帧，不在主线程一口气补完整段，保证不同设备不会因执行速度安装不同地图。手机帧率仍需实测。

重试、存档恢复和退出会取消并释放未完成的验证克隆。合法布局验证失败仍保留原有拒绝策略，没有删除障碍、放宽路线断言或更改移动、碰撞、生成随机数及帧同步消息协议。

回归命令（Godot 4.7.1，工作目录为项目根目录）：

```bash
Godot --headless --path . --script res://tests/web_generation.gd
Godot --headless --path . --script res://tests/online_lockstep.gd
ONLINE_TRANSPORT=ws Godot --headless --path . --script res://tests/web_online_generation.gd
ONLINE_TRANSPORT=mixed Godot --headless --path . --script res://tests/web_online_generation.gd
```

`web_generation.gd` 覆盖不同切片大小与原 worker 的完整布局一致、合法输入打开教学门、后续真实障碍及生产展示节点、原生/无线程逐帧一致、单机路径、重试和退出释放。`web_online_generation.gd` 继承原有联机断言，仅把第二个客户端能力设为无后台线程，额外核对确实使用分帧验证安装障碍。原有联机测试及其阈值未修改。

发布后两位玩家都应刷新网页，避免混用修复前后不同生成逻辑的旧客户端。测试结果不代表手机实机触屏、帧率和公网完整对局已通过。

本次本机验收记录：无线程专项 26/26；原有 ENet 21/21；WebSocket + 无线程客户端 22/22；ENet/WebSocket 混合 + 无线程客户端 22/22；地址与 /ws 路径 16/16。真实单线程 WebAssembly 自动场景也完成 26/26，开门后生成 4 段、24 个障碍及 24 个生产展示节点。

额外补跑的历史 `road_charge_gate.gd` 为 38/39，“合法交换角色路线仍开门”在未修改基线与修复分支上均失败；没有为此修改测试或玩法，不把它报告成通过。手机音频、触屏与实际帧率仍待用户试玩。

## 所有机关前持续预计算与模型预热

原先只在第一关教学期间准备四段，后续关门仍可能阻断新任务；证明到固定安装点来不及时会集中补算。新版从开始游戏到后续关卡，持续用独立随机状态副本维护前方四段，并分帧证明。正式随机序列、验证断言和地图安装边界不变。

生产场景在应用模拟帧前调用 `prepare_frame()`，未准备好时只让出本次帧、保持渲染响应；每次执行有限验证步及约2ms软预算，禁止走旧直接驱动Run的集中补算兼容路径。若非常慢的设备仍需等待，会显示“正在准备前方道路…”，不保证完全没有等待，但不会为补完一整段阻塞UI。

已证明的前方路段会提前逐个创建隐藏障碍模型；一轮最多创建一个。如果当前安装帧需要的模型还没备齐，先分帧准备，不在开门瞬间批量创建。已有障碍按稳定ID及几何尺寸保留，不再因领取金币、回收其他障碍或一般刷新把所有巨岩销毁重建；备用模型池有数量限制。

联机保持原有缓冲节奏，并限制积压时单次追帧量；准备完成前不从接收队列取走帧，当前帧的命令只执行一次。就绪后使用原帧号、输入与命令继续，既不跳帧，也不把等待时间加入模拟。UDP、WebSocket和混合联机的消息协议不变，双方应刷新到同一客户端版本。

单个验证步或单个模型的创建不能抢占，所以预算为软上限；浏览器GPU、着色器编译和极慢手机仍需实机确认。旧测试直接调用Run.step而不经过生产场景准备入口时，保留同步兼容路径以维持既有测试语义，生产场景通过计数断言确认未执行该路径。

专项：`tests/gate_stream_preload.gd` 连续通过教学和后续机关，检查持续预计算、完整模型、逐帧一致及不集中补算；`tests/frame_prepare_atomic.gd` 强制延后帧，检查保留队列、重试/暂停命令只执行一次；`tests/gate_online_frames.gd` 使用真实中继及生产客户端，在第二客户端开局与重试首帧各制造6次准备延迟，以420个共同帧检查连续编号、命令单次执行和状态一致；其输入保持中立，路线及奖励验收仍由未修改的既有联机回归执行。原有生成、联机和碰撞测试断言未放宽。

存档与验证入口快照明确排除 `cooperative_job` 等调度句柄；恢复只重建新任务，不重新挂接已取消的任务对象。

存档中已证明的历史路段也经过准备入口再安装，不能绕过分帧模型预热直接批量装入。
