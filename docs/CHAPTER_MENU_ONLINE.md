# 主界面选章、章节按需下载、本机缓存与联机优化（2026-10-21）

任务分支 `feature/chapter-menu-online-cache`，从 `test` 的 `505e544` 创建，独立工作区 `D:/ConjoinedTwins-task-temp/chapter-menu-online-cache`。未合并、未推送、未部署。

## 做了什么

### 1. 主界面与章节选择

- 打开游戏先进入主界面（`scripts/main_menu.gd`），四张章节卡片：第一章 穿林入村、第二章 水车河道、第三章 矿道归航、战斗训练。代码里的“三关旅程 + 战斗训练”合起来就是用户说的四个章节。
- 封面不是另画的插图，而是用生产场景在隐藏窗口里渲染的真实画面（`build-tools/capture_chapter_covers.gd` 取景、`build-tools/make_chapter_covers.py` 裁切），所以和各章实际画面一致：村口怪物潮、河岸水车、夜晚遗迹、林间训练道路。四张 960×540 共约 290 KB，放在主包里。
- 选中卡片后背景换成该章封面并缓慢推移，左侧显示章节名、六个区域、简介和“需下载 xx MB / 已缓存 · 秒开 / 已载入”。点“进入章节”（或再次点卡片、回车）才开始下载。键盘左右键、手柄可选章；窄屏改为两行两列。
- 进入章节后，开始页仍是原来的单人＋搭档 / 远程双人 / 难度 / 设置；原“战斗训练”切换按钮改为“返回主界面 · 选择其他章节”，暂停页“回到主页”回到章节选择，并释放上一章场景（网页内存不累积）。
- 直接运行 `scenes/journey.tscn`（测试、旧入口）行为不变；无界面运行或带 `-- --chapter=N` 时跳过主界面直接进入该章。

### 2. 章节按需下载

网页版原来把全部资源打进一个 `index.pck`（2026-10-20 时约 160 MB，压缩传输约 135 MB），首次打开要等它全部下完。现在：

- `build-tools/chapter_usage.py` 为每章（含训练）启动一个无头进程，多种子把整章流式加载走一遍，记录实际用到的资源，写入 `build-tools/chapter_usage.json`。
- `build-tools/split_web_pack.py` 在导出后把整包逐字节拆开（不重新导出、不改资源）：
  - 主包 `index.pck`：脚本、场景、着色器、界面、封面、字体——打开网页就能显示主界面；
  - `common`：所有章节都用的资源（以及用量记录里从未出现过的资源，宁可多下载不缺资源）；
  - `c01`、`c013` 等：只被部分章节使用的资源，按使用组合分组，多章共用的只下载一次；
  - 压缩贴图再按格式分包：桌面浏览器只下载 s3tc，手机只下载 etc2，各省一半贴图流量。
- 游戏内 `ChapterPacks`（自动加载）读取 `packs.json`，选章时只下载这一章缺的包，带进度、速度和剩余时间，失败自动重试两次，仍失败显示“重试”。结算后进入下一章前，本章游玩期间已在后台预取下一章。
- 原生（Windows / Mac / iOS）与未拆包的网页没有清单，全部视为就绪，行为与之前相同。

拆包大小见下文“实测”。

### 3. 刷新后不再重新下载

- 网页外壳 `web/shell.html` 在启动引擎前注册 Service Worker（`web/sw.js`，导出时写入本次构建的文件清单）。
- 引擎、主包和所有章节包按“路径 + 内容哈希”存进浏览器 Cache Storage：再次打开或刷新页面时直接从本机读取，不走网络。
- 发布新版本时，内容没变的章节包哈希不变、继续使用；变了的自动换新，旧条目在新版本激活时删除。
- `index.html`、`packs.json`、`sw.js` 和 `/ws` 联机始终走网络。主包里写有构建号，与 `packs.json` 不一致（浏览器还在用旧主包）时提示刷新，避免新旧数据混用。
- 需要 https（nyat.app 隧道满足）或 localhost；不支持时退回普通浏览器缓存并在启动页说明。

### 4. 载入画面与进度条

所有载入画面使用同一套视觉：对应章节封面缓慢推近，左下章节名与区域路线，底部“能量连线”进度条——左端 01（青）右端 02（橙），能量沿连线从 01 流向 02，和游戏里两人之间的能量绳同色；显示阶段、已下载/总量、速度与剩余时间、百分比，以及每 6 秒轮换一条该章节的玩法提示。

- **网页启动画面**（`web/shell.html`）：引擎与主包下载，背景为第一章封面；显示是否从本机缓存载入。
- **章节载入画面**（`scripts/loading_screen.gd`，由入口 `scripts/journey_boot.gd` 驱动）：下载章节数据 → 读取角色与地形 → 准备沿途场景。
- **联机入场画面**：点“连接队友”后显示步骤清单：连接联机服务器 → 等待队友加入 → 同步章节 → 下载章节数据 → 准备沿途场景 → 等待双方就绪；下方两张 01/02 状态卡显示双方“下载中 xx% / 准备场景中 / 已就绪”，可随时“返回”断开。
- **章节之间**：下一章数据未就绪时显示该章载入画面，下载完自动继续。

### 5. 联机

- 联机章节由 01 号玩家在主界面的选择决定；02 号自动下载、准备同一章。
- 双方各自确认“本章数据已下载、场景已准备”后才真正出发；先按“出发”的一方显示“等待队友载入完成…”，双方就绪后自动出发。确认、换章都在共同帧里生效，两端状态一致。
- 某一端还在下载时只是暂缓消化服务器帧，下载完按原编号追帧，不改变模拟结果、不丢输入。结算时本机还没拿到下一章，会先不确认，队友等双方都按下。
- 协议升到 7：服务器每帧广播从 `var_to_bytes` 数组（按编码格式估算约 100 字节）改为 11 字节二进制（有操作命令时才附加），客户端输入改为 4 字节、只在变化时上传（另每秒补发一次）。服务器与客户端须同时更新：旧客户端会收到“版本不一致”提示。

## 1 MB/s 能否流畅联机

能。卡顿的根源不是游戏过程的带宽，而是“先下载 100 多 MB 才能进游戏”。

- 帧同步只传输入：协议 7 每个客户端下行约 11 字节 × 60 帧/秒 ≈ 0.7 KB/s 负载，加上 WebSocket、TLS、TCP 头后约 5–6 KB/s；上行只在按键变化时发 4 字节。两人合计远低于 1 MB/s 的 2%。
- 1 MB/s 下，首次进入的等待主要是下载：到主界面约 8.8 MB（约 8 秒），再加所选章节的数据包 77–133 MB（见实测）。第二次及以后全部来自本机缓存，基本无需等待。
- 真正影响手感的是延迟和抖动（隧道绕行、TCP 重传），不是带宽。帧同步本身已有积压追帧和 2 帧缓冲。

## SakuraFrp 与服务器方案

| 方案 | 费用 | 效果 | 说明 |
| --- | --- | --- | --- |
| 继续用 SakuraFrp 免费隧道 | 0 | 隧道限速约 10 Mbps（≈1.2 MB/s） | 现在的瓶颈主要是首次下载；拆包＋缓存后已能接受 |
| SakuraFrp 白银 VIP | ¥20/月 | 隧道限速约 36 Mbps（≈4.3 MB/s） | 首次下载提速约 3.6 倍，部署方式不变，最省事 |
| 静态文件放云存储/CDN，Mac mini 只做联机中继 | 按流量计费，几十 MB × 人次，个人试玩每月几元 | 下载走 CDN，速度取决于玩家宽带 | 推荐长期方案；联机只占 KB/s，隧道够用 |
| 国内轻量云服务器跑中继＋网页 | 新用户首年约 ¥38–109（3–6 Mbps 固定带宽） | 公网直连、延迟更稳 | 国内机型带宽小（3 Mbps≈0.4 MB/s），首次下载反而更慢；适合只跑中继 |
| 境外/香港轻量服务器 | 约 ¥35–60/月起（标称 200 Mbps 峰值） | 带宽大 | 国内访问延迟与线路质量不稳定，需实测 |

价格、带宽来自 2026-10-21 查阅的 [SakuraFrp 官网](https://www.natfrp.com/) 与 [腾讯云轻量服务器活动页](https://cloud.tencent.com/act/pro/lhsale) 等，活动价随时变化，以下单页为准。

建议顺序：先部署本次拆包＋缓存（免费）；首次下载仍嫌慢就开 SakuraFrp 白银 VIP；长期再把 `builds/web/` 的静态文件放到对象存储＋CDN，Mac mini 只保留 `/ws` 中继。

## 实测（本机导出，brotli 压缩后的传输量，桌面 s3tc；手机 etc2 相差不到 1 MB）

| 内容 | 拆包前 | 拆包后 | 1.2 MB/s（SakuraFrp 免费）首次耗时 |
| --- | --- | --- | --- |
| 显示主界面前 | 全部约 165 MB | 引擎 7.1 + 主包 1.7 = **8.8 MB** | 约 8 秒（原约 2 分 20 秒） |
| 第一章 穿林入村 | 已含在上面 | 133.3 MB | 约 111 秒 |
| 第二章 水车河道 | 同上 | 123.2 MB | 约 103 秒 |
| 第三章 矿道归航 | 同上 | 77.3 MB | 约 64 秒 |
| 战斗训练 | 同上 | 79.3 MB | 约 66 秒 |
| 四章全部 | 约 165 MB | 148.4 MB（另一贴图格式不再下载） | — |
| 第二次打开 / 刷新 | 依赖浏览器 HTTP 缓存，每次要向服务器确认 | 引擎、主包、已下章节全部来自本机缓存 | 基本只剩启动时间 |

- 第一章用到了游戏里大部分资源（村庄、森林、全部怪物轮换），所以单章节省有限；第三章、训练节省约一半。多章共用的包只下载一次：玩完第一章再进第二章，只需再下第二章独有的部分。
- 本次还顺带把三种新怪物（树根蜘蛛、哥布林投弹手、河蟹骑士）运行时不用的未绑骨原件从网页包排除（与已有的其他怪物做法一致，只用 `rigged/` 版本），各章音乐改为只进对应章节的包，`common` 从 39 MB 降到 23 MB。均不改变画质。
- 进一步压缩体积会降低画质，仍按原约定留给 `chore/web-pck-diet-lossy-options` 分支由你逐项决定。

## 验证（执行者自测，Windows 本机，Godot 4.7.1 headless；Controller 独立测试 tests=[]）

| 检查 | 结果 |
| --- | --- |
| `tests/chapter_menu.gd`（新增：主界面不加载生产场景、选章进入对应章节、回主页释放场景、训练入口、章节资料一致、帧编解码） | 19/19 通过 |
| `tests/online_chapter_sync.gd`（新增：UDP + WebSocket 混合，01 号选第二章、02 号选第三章 → 两端同步到第二章，待定出发、双方就绪后同帧出发，242 个共同帧指纹一致） | 12/12 通过 |
| `tests/journey_online.gd` / `journey_combat_online.gd` / `frame_prepare_atomic.gd` / `journey_rescue_lifecycle.gd` | 10/10、18/18、7/7、32/32 通过 |
| 联机流量（`journey_online` 420 帧） | 下行每帧约 12.3 字节负载；上行整段约 0.5 KB（约 70 B/秒） |
| `python build-tools/check_journey_performance.py`（最终源码） | 26/26 通过，报告 `%TEMP%/ConjoinedTwins-performance/chapter-menu-final/summary.json` |
| `python build-tools/prepare_web.py` 导出 + 拆包 + 预压缩 | 通过 |
| `python build-tools/verify_web_packs.py`（本机 HTTP 下载，每章只挂主包 + 本章数据包，用与生成用量不同的 4 个种子整章流式加载） | 4 章全部 0 缺失 |
| 隐藏窗口截图 `build-tools/capture_menu_screens.gd` | 主界面与载入画面版面正常（仅自查，不算可见 GUI 验收） |

与未改动基线（`505e544`）逐项对照、两边结果相同的既有问题，没有为此改测试：`online_lockstep.gd`、`gate_online_frames.gd`、`web_online_generation.gd` 启动即崩溃；`web_generation.gd` 在 narrow_triple 之后间歇性引擎崩溃（CowData，基线 3/3 次复现，本分支 1/3 次通过 41/41）；`online_backlog_catchup.gd` 2 项、`journey_loading.gd` 2 项（18 区域布局哈希与基线逐项相同）、`release_integration.gd` 1 项失败。`high_fps_boot_check.gd` 需要 `DENSE_FRAME_REPORT` 环境变量，场景本身已准备完成。

未验证（需要你试玩）：浏览器内 Service Worker 缓存与刷新后秒开、手机 etc2 贴图分包、真实公网 1 MB/s 下的下载与联机手感、iPhone Safari 的存储配额、可见画面与触屏操作。本机 headless 会同时挂载 s3tc 与 etc2 两种贴图包，不能代表浏览器只下一种的情况。

## 部署注意

1. 在 Mac mini 上按 [网页版联机说明](WEB_ONLINE.md) 重新导出：`python3 build-tools/prepare_web.py --engine …`。导出后会自动拆包、生成 `packs.json`、`sw.js`、`loading_bg.jpg` 并预压缩全部 `.pck`。
2. 把 `builds/web/` 整个目录（含 `packs/`）同步到 `CT_WEB_ROOT`。
3. 协议从 6 升到 7，**中继也要用新代码重启**；两人都刷新页面。
4. Caddyfile 不需要改：`precompressed br gzip` 同样适用于 `packs/*.pck`。
5. 新增或删除资源、改动章节内容后，先运行 `python build-tools/chapter_usage.py` 更新用量记录再导出。

## Windows 本机发布（2026-10-21 起替代 Mac mini）

SakuraFrp 隧道：TCP，节点“浙江三线PLUS7”，公网端口 57412 → 本机 `127.0.0.1:8080`，需开启自动 HTTPS（网页 Service Worker 与 wss 联机都要求 https）。

本机没有 Caddy，改用 `deploy/windows/serve_web.py`（只用 Python 标准库），职责与 `deploy/macmini/Caddyfile` 相同：静态文件优先发预压缩 `.br/.gz`、`.wasm` 正确类型、`no-cache` + ETag；`/ws` 透传给联机中继 WebSocket 端口 24681。

```
python build-tools/prepare_web.py                                                    # 导出 + 拆包 + 预压缩到 builds\web
powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1 -Publish     # 复制到 D:\ConjoinedTwins-web\site 并后台启动
powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1 -Stop        # 停止
```

- 站点目录固定为 `D:\ConjoinedTwins-web\site`（工程外），其他任务重新导出 `builds\web` 不会影响正在发布的版本；要更新时再 `-Publish`。
- 中继用 `--main-pack 站点\index.pck` 运行，与正在发布的网页同一份代码，协议版本必然一致。
- 进程无窗口运行，PID 记录在 `D:\ConjoinedTwins-web\*.pid`，日志在 `D:\ConjoinedTwins-web\logs\`；脚本只停止自己记录的进程。重启电脑后需重新运行（未注册开机自启）。也可双击 `deploy\windows\启动网页服务器.cmd`。
