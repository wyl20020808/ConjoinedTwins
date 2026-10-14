# 网页版联机说明

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
