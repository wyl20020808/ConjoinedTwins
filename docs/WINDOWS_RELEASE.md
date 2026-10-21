# Windows 桌面版与联机（2026-10-21）

用户决定不再以网页版为主，改为把 Windows 程序直接发给朋友联机。

## 打包

```
python build-tools/prepare_windows.py
```

- 首次运行从 Godot 官方 GitHub 发布包按 HTTP Range 只读取 `windows_release_x86_64.exe` 一个条目（约 109 MB），存到被 Git 忽略的 `build-tools/cache/`，来源与 CRC 记录在 `windows-template-source.json`，不做全局安装。本机代理访问 GitHub 下载域名偶发 TLS 中断，重新运行会从已缓存的分段续传。
- 导出预设 “Windows Desktop”：资源全部在 `ConjoinedTwins.pck`（只含桌面 s3tc 贴图，约 170 MB），不需要按章节下载；排除列表与网页版相同（未用的原件、测试、文档、构建工具）。
- 产物：`builds/windows/ConjoinedTwins/`（`ConjoinedTwins.exe`、`ConjoinedTwins.pck`、`使用说明.txt`）与压缩包 `builds/windows/ConjoinedTwins-Windows.zip`（约 195 MB）。不入库。
- 程序没有数字签名，Windows 首次运行会弹 SmartScreen，按说明点“更多信息 → 仍要运行”。

## 联机

- 桌面版的“远程双人”地址框默认填 `wss://www.u4139693.nyat.app:57412/ws`（`scripts/net_client.gd` 的 `DEFAULT_SERVER`）：经现有 SakuraFrp TCP 隧道（自动 HTTPS）到主机电脑的 `deploy/windows/serve_web.py`，再由 `/ws` 转给联机中继。不需要再开 UDP 隧道。
- 启动参数 `-- --server=地址` 可覆盖；玩家改过且连接成功的地址保存在 `user://online.cfg`，下次沿用（无界面测试不保存）。
- 主机本人也可以用同一个地址；想更低延迟可改填 `127.0.0.1`（直连本机 UDP 24680）。两种连接进同一房间。
- 主机电脑需保持开机，运行 `deploy\windows\启动网页服务器.cmd`（同时启动联机中继）和 SakuraFrp。中继来自站点目录的网页主包，协议与桌面版同为 7；以后改了联机协议，要同时重新发布站点（`start_server.ps1 -Publish`）和重新打包 Windows 版。

## 验证

见本轮提交说明与最终报告：导出程序本身的资源完整性巡检、两个导出程序经公网服务器的联机冒烟（`tests/public_online_smoke.gd`，会占用线上房间约半分钟）。
可见画面、真实键鼠/手柄手感、朋友那台电脑的显卡兼容性与公网延迟需要实际试玩。
