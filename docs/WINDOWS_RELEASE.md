# Windows 桌面版与联机（2026-10-21）

用户决定不再以网页版为主，改为把 Windows 程序直接发给朋友联机。

## 打包

### Windows 安装向导（2026-10-23）

发给朋友时使用 `builds/windows/installer/<版本>/共生连线_Setup.exe`。文件名统一使用游戏名称和标准安装标识，版本号保存在安装信息和构建记录中；不同版本放在各自目录，保留历史产物。朋友双击安装，按中文向导选择目录，默认创建桌面快捷方式；安装结束可立即启动。以后双击桌面或开始菜单中的“共生连线”即可游玩。Windows 设置的应用列表和开始菜单提供卸载入口。

构建电脑需要 Inno Setup 6.7 或更新版本。安装器编译器来自 [Inno Setup 官方下载页](https://jrsoftware.org/isdl.php)，通过 `--iscc` 指定路径，不要求加入 PATH。朋友电脑不需要 Python、Godot 或 Inno Setup。

```powershell
python build-tools/package_windows_installer.py --iscc "你的 Inno Setup 目录/ISCC.exe"
```

该命令复用 `prepare_windows.py` 完成导出、资源拆包，再生成单文件安装器。已有完整导出时可避免重复导出：

```powershell
python build-tools/package_windows_installer.py --skip-export --iscc "你的 Inno Setup 目录/ISCC.exe"
```

- 安装仅针对当前用户，默认路径为 `%LOCALAPPDATA%\Programs\ConjoinedTwins`，无需管理员权限；可在向导中更换目录。支持 Windows 10/11 x64；其他平台仍走各自打包流程。
- 选择目录时，浏览窗口提供“新建文件夹”，可以创建并重命名安装目录。用户选中的目录就是最终安装位置，不再自动追加 `ConjoinedTwins` 子目录；不更改路径时仍使用上述默认目录。通过 Inno Setup 的 `AppendDefaultDirName=no` 启用，依据见 [官方说明](https://jrsoftware.org/ishelp/topic_setup_appenddefaultdirname.htm)。
- 安装器包含主程序、主包、数据包清单和全部校验过的数据包，首次安装不需要下载游戏资源。联网更新继续使用既有云更新，更新文件写入玩家用户数据目录。
- 固定 AppId 让后续安装复用原安装位置和卸载项。重复安装覆盖本安装器提供的文件；卸载只处理安装文件和快捷方式，保留玩家设置及已下载的云更新。
- 不会自动关闭正在运行的游戏，也不会重启系统。安装前请先退出游戏。
- 构建前逐个检查数据包大小与 SHA-256；编译日志与输入文件哈希存入安装器目录下的 `evidence-*/build.json`。同版本安装器已存在时停止，保留原件。
- 这是未签名的测试安装器，Windows 可能显示未知发布者或 SmartScreen 提示。安装器外观与代码签名信誉是不同事项；本流程没有配置证书。
- 此命令只构建本地产物，不发布更新、不修改线上清单、不重启联机服务。现有 `publish_update.py` 的完整下载链接仍发布 ZIP，安装器可单独发给朋友。

安装向导使用 Inno Setup 自带机制。简体中文翻译保留在 `build-tools/installer/ChineseSimplified.isl`，来源为官方源码库 `is-6_7_3` 标签的 `Files/Languages/Unofficial/ChineseSimplified.isl`，保留原作者说明；原文件 SHA-256 为 `7d544b9bb1d142cfa11f2e5d3cc8abe2e55f8e066c5124e3772675aa236e1278`。

本轮本地验证（2026-10-23）：对当前线上同版本 `20261023T010711Z-5608906` 的完整资源目录封装，安装器约 227 MB。`verify_windows_installer.py` 实际执行中文带空格目录安装、重复安装、逐文件哈希校验、真实桌面与开始菜单快捷方式检查、卸载项检查和卸载；这些步骤通过，测试安装与快捷方式已清理，额外的用户文件保留验证通过。数据包篡改、越界路径与非法版本号拒绝检查通过。综合验证脚本仍退出 1：已安装游戏在 headless `--quit-after 120` 退出时报告 2 个 ObjectDB 实例泄漏、1 个资源仍在使用；原便携包在独立用户数据目录以相同参数复现同样日志，因此游戏启动/退出检查列为失败，不能以安装生命周期通过代替。日志在工程外 `D:/ConjoinedTwins-task-temp/windows-installer-acceptance-final-20261023`，原包对照日志在 `D:/ConjoinedTwins-task-temp/windows-installer-acceptance-20261023/baseline-startup.log`。可见向导、真实玩家输入和朋友电脑兼容性未验收；Controller 独立测试未运行。

本机复验入口如下（仅 `idle` 允许，会短暂创建真实快捷方式；检测到已有安装或同名快捷方式时停止，不覆盖用户现有安装）：

```powershell
python build-tools/verify_windows_installer.py "安装器.exe" --source "已导出的完整资源目录" --evidence "新的工程外证据目录"
```

### 原有便携 ZIP

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

## 双机恢复修复（任务分支，尚未合并）

`fix/native-online-recovery` 将联机协议升级为 8，加入断流主动补帧、UDP 短按跳跃恢复、双向脚本指纹握手、角色与绳索显示平滑以及分层诊断。Windows 打包入口会自动刷新指纹；更新时须同步更新中继与双方 EXE。具体行为、验证与未验收边界见 [双电脑原生联机恢复](NATIVE_ONLINE_RECOVERY.md)。本轮没有替换正在运行的服务或发布新包。

## 游戏专用 UDP 隧道（2026-10-22）

主机改用 SakuraFrp 游戏专用节点的 UDP 隧道（本地 `127.0.0.1:24680`），`DEFAULT_UDP_SERVER` 改为节点 IP `103.91.208.133:54145`。该节点要求用 IP 连接；域名 `frp-top.com` 在开着代理（Fake-IP）的电脑上会被解析为代理内部地址，UDP 无法直达。默认连接顺序不变：本机中继 → UDP 隧道 → wss。更换节点或端口后需重新打包，并用新包的 `.pck` 重启中继（指纹覆盖全部脚本）。

## 云更新（2026-10-23）

目的：发一次安装包后，以后更新不再重新发包；换隧道、换节点也不必重新打包。

- **安装包结构**：`prepare_windows.py` 导出后按章节用量拆包，`ConjoinedTwins.pck` 只留主包（脚本、场景、界面，约 6 MB），贴图、模型、音频放在 `packs/` 下的数据包里（文件名带内容哈希，`packs.json` 记录大小与 SHA-256），启动时由 `ChapterPacks` 一次挂载。安装包总大小不变。
- **发布**（主机电脑）：`python build-tools/publish_update.py`。导出后把主包和安装包里同一批数据包写到 `D:\ConjoinedTwins-web\update`，最后原子替换 `manifest.json`。只改了玩法时，玩家通常只需下载新主包；保留上一版文件，正在下载的玩家不会断。`--skip-export` 复用已导出的版本，`--no-installer` 不附带完整安装包。
- **联机地址与备用更新链接**：存放在 `D:\ConjoinedTwins-web\update-config.json`（主机本地，不入库，首次发布按 `net_client.gd` 内置地址生成）。换隧道或节点后改这个文件，再运行 `publish_update.py --servers-only`，不用重新打包；玩家下次检查更新时自动换用（`net_client.gd` 的 `udp_server()` / `ws_server()` 优先用清单下发的地址）。
- **提供下载**：`serve_web.py --update-root` 以 `/update/` 提供更新目录，与网页站点分开存放，`start_server.ps1 -Publish` 的 robocopy /MIR 不会删掉它。`start_server.ps1` 检测到更新目录时自动加上该参数，并让联机中继运行清单里的主包，保证与玩家更新到的版本一致。发布新版本后需重新运行 `启动网页服务器.cmd` 重启中继。
- **玩家端**（`scripts/cloud_update.gd`、`scripts/update_panel.gd`）：导出的桌面程序每次启动先读取 `<更新链接>/manifest.json`，依次尝试玩家填写的链接、清单给的备用链接、内置默认链接。有新版本时先在本机找同名、同 SHA-256 的文件（已下载的，或安装目录 `packs/` 里自带的），只把缺少的下载到 `user://ct-update/files/`，逐个校验 SHA-256，再用 `--main-pack` 重启自身进入新版本；`ChapterPacks` 在新进程启动时挂载该版本的全部数据包。已是最新或连不上时直接进入主界面；连不上但本机有更新过的版本时进入该版本。主界面右上角“检查更新”可修改链接（每行一个）并立即检查。
- **版本号**：`prepare_windows.py` 导出时把“UTC 时间-提交号”写入 `ct_release.txt` 并打进包内，字符串比较即新旧；工作区有未提交改动时带 `-dirty`。
- **边界**：exe 本身不更新；引擎版本变化时清单的 `engine` 不匹配，界面提示下载完整安装包（`/update/installer/`）。更新文件只按清单里的 SHA-256 校验，没有签名，链接必须来自主机本人。主机关机时玩家检查不到更新，但仍能用已有版本启动。
- **联机指纹修复**：导出包的脚本目录只列出 `.gdc` / `.remap`，原来的指纹计算读不到任何源码，所有导出包都得到同一个空内容哈希，版本不同也能进同一房间。现在读不到源码时改用打包时生成的清单。
- **验证**（2026-10-23，临时目录与隔离的用户数据目录，未动正式服务）：发布 A、B 两版，B 只新增 5.6 MB 主包、14 个数据包全部复用；A 版客户端经本机测试服务器下载 202 MB、校验后重启进入 B，B 进程挂载数据包后能完整加载 `journey.tscn`，清单下发的联机地址生效；已是最新时直接进入；更新服务器不可达时退回已下载的 B。可见界面、经公网隧道下载与朋友电脑上的实际更新未验证。
- **安装包资源复用验证**（2026-10-23，同样在临时目录）：新格式安装包 A 启动时挂载自带数据包并完整加载 `journey.tscn`；发布 B 后 A 更新只下载 5.4 MB 主包，14 个数据包直接引用安装目录里的文件，重启进入 B 后完整加载。好友装完后第一次更新不再重新下载全部资源。
- **正式上线**（2026-10-23）：更新与 wss 走 SakuraFrp TCP 隧道 `www.u4139693.nyat.app:53569`（本地 `127.0.0.1:8080`，必须开启自动 HTTPS；该节点拦截明文 HTTP），联机 UDP 走 `103.91.208.133:54145`（本地 `127.0.0.1:24680`）。首个正式版本 `20261023T010711Z-5608906`。公网实测：清单与主包经 HTTPS 下载正常（约 1.7 MB/s）；旧版测试客户端经公网更新只下载 5.4 MB 主包并重启进入新版；经 UDP 与 wss 各两客户端进入同一房间并开局。首次双人探针曾报一次“版本不一致”，随后复查双方指纹一致、重跑通过，原因未复现。
