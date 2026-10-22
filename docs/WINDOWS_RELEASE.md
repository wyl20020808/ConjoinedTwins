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

## 联机流畅度第一轮（2026-10-22）

依据 2026-10-22 00:28–00:45 两局的中继日志（每人约 41 条、每条 10 秒）：队友（01 号，经 UDP 隧道）延迟中位 106 毫秒、抖动 34 毫秒、每 10 秒卡顿中位 18 次；主机（02 号，本机直连）延迟 11.5 毫秒却仍每 10 秒卡顿 8 次。

原因与改动：

1. **断流后整段冻结**：上一版缓冲见底后停住，直到攒满目标帧数（队友约 4 帧，停 50–70 毫秒）。现参照帧同步游戏的时间伸缩：见底只等下一帧到达；缓冲少于目标时每 4 帧少走一帧、多于目标时每 4 帧多走一帧，积压很多才快速追帧（`net_client.gd` 的 `playout_limit`）。抖动模拟（`tests/online_jitter_buffer.gd`）中 ≥50 毫秒的停顿 29 次 → 2 次，帧序完整。
2. **中继发帧不准时**：原先在物理帧里累加，与主机游戏同机时物理帧成串挤在一起。现按单调微秒时钟每 1/60 秒准点发帧，主循环提到 1000 次/秒；`start_server.ps1` 把中继进程优先级调为“高于正常”。
3. **快的一方等慢的一方**：客户端每 15 帧回报进度（`ack`），服务器领先最慢一方超过 90 帧（1.5 秒）即暂停出帧，恢复后从当前时刻重新计时，不一次补发一大串。
4. **镜头平滑**：联机时镜头前后方向平滑跟随（约 60 毫秒收敛），偶尔少走或多走一帧不再整屏一顿；只影响显示，不进入模拟。

未在两台真实电脑上验证；队友的基础延迟（约 106 毫秒）属于线路问题，需更换离双方更近的 SakuraFrp 节点才能降低。
`journey_combat_online.gd` 在 `ONLINE_TRANSPORT=mixed` 下有 3 项失败，改动前同样存在：测试默认 `games[0]` 是 01 号，混合传输时 WebSocket 一端先连上拿到 01 号。按实际编号检查时，UDP 玩家的开火、换弹、丢枪、后退均两端同步。
