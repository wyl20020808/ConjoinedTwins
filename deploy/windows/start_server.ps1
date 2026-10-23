<#
Windows 本机发布网页版：网页服务（127.0.0.1:8080）+ 联机中继（UDP 24680 / WebSocket 24681），后台无窗口运行。
SakuraFrp TCP 隧道（开启自动 HTTPS）把公网地址转到 127.0.0.1:8080，队友打开隧道地址即可游玩和联机。

用法（PowerShell，在工程根目录）：
  powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1 -Publish   # 先把 builds\web 复制到站点目录再启动
  powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1            # 只（重新）启动服务
  powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1 -Stop      # 停止本脚本启动的服务

中继直接运行站点里的主包（--main-pack），保证联机协议与正在发布的网页版本一致；
发布过桌面版云更新（build-tools\publish_update.py）时改用更新目录里的主包，与玩家自动更新到的版本一致，
网页服务同时以 /update/ 提供更新目录。
只停止本脚本记录在 PID 文件里的进程，不影响其他 Godot 或 Python。
#>
param(
	[string]$Site = "D:\ConjoinedTwins-web\site",
	[string]$Build = (Join-Path $PSScriptRoot "..\..\builds\web"),
	[string]$Engine = "D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe",
	[string]$Python = "python",
	[int]$Port = 8080,
	[switch]$Publish,
	[switch]$Stop
)
$ErrorActionPreference = "Stop"
$State = Split-Path $Site -Parent
$Logs = Join-Path $State "logs"
New-Item -ItemType Directory -Force $Logs | Out-Null

function Stop-Recorded([string]$Name) {
	$pidFile = Join-Path $State "$Name.pid"
	if (Test-Path $pidFile) {
		$id = [int](Get-Content $pidFile)
		# Godot 控制台版会再启动一个真正的引擎子进程，端口由子进程占用，需一并停止。
		Get-CimInstance Win32_Process -Filter "ParentProcessId=$id" -ErrorAction SilentlyContinue | ForEach-Object {
			Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
		}
		$process = Get-Process -Id $id -ErrorAction SilentlyContinue
		if ($process) { Stop-Process -Id $id -Force; Write-Output "已停止 $Name (PID $id)" }
		Remove-Item $pidFile
	}
}

Stop-Recorded "web"
Stop-Recorded "relay"
if ($Stop) { exit 0 }

if ($Publish) {
	$source = (Resolve-Path $Build).Path
	if (-not (Test-Path (Join-Path $source "packs.json"))) { throw "构建目录缺少 packs.json：$source（先运行 build-tools\prepare_web.py）" }
	New-Item -ItemType Directory -Force $Site | Out-Null
	# /MIR 让站点与构建完全一致（删除旧版本的章节包）；robocopy 返回码小于 8 都表示成功。
	robocopy $source $Site /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
	if ($LASTEXITCODE -ge 8) { throw "复制网页失败，robocopy 返回 $LASTEXITCODE" }
	Write-Output "已发布 $source -> $Site"
}
if (-not (Test-Path (Join-Path $Site "index.pck"))) { throw "站点目录没有网页：$Site（加 -Publish 先发布）" }
$Update = Join-Path $State "update"
$RelayPack = Join-Path $Site "index.pck"
$UpdateManifest = Join-Path $Update "manifest.json"
if (Test-Path $UpdateManifest) {
	$core = Join-Path $Update ((Get-Content $UpdateManifest -Raw -Encoding UTF8 | ConvertFrom-Json).core.file)
	if (Test-Path $core) { $RelayPack = $core; Write-Output "中继使用云更新主包：$core" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$relay = Start-Process -FilePath $Engine -WindowStyle Hidden -PassThru `
	-ArgumentList @("--headless", "--main-pack", "`"$RelayPack`"", "res://scenes/net_relay.tscn") `
	-RedirectStandardOutput (Join-Path $Logs "relay-$stamp.log") -RedirectStandardError (Join-Path $Logs "relay-$stamp.err.log")
Set-Content (Join-Path $State "relay.pid") $relay.Id
# 中继与主机的游戏同机运行：调高优先级，发帧节奏不被游戏渲染挤乱。控制台版会再起一个引擎子进程，两者都调。
Start-Sleep -Milliseconds 800
foreach ($id in @($relay.Id) + @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($relay.Id)" | ForEach-Object { $_.ProcessId })) {
	$process = Get-Process -Id $id -ErrorAction SilentlyContinue
	if ($process) { try { $process.PriorityClass = "AboveNormal" } catch { Write-Output "无法调整中继优先级：$_" } }
}
$webArgs = @("-u", "`"$(Join-Path $PSScriptRoot 'serve_web.py')`"", "--root", "`"$Site`"", "--port", $Port)
if (Test-Path $Update) { $webArgs += @("--update-root", "`"$Update`"") }
$web = Start-Process -FilePath $Python -WindowStyle Hidden -PassThru `
	-ArgumentList $webArgs `
	-RedirectStandardOutput (Join-Path $Logs "web-$stamp.log") -RedirectStandardError (Join-Path $Logs "web-$stamp.err.log")
Set-Content (Join-Path $State "web.pid") $web.Id
Write-Output "联机中继 PID $($relay.Id)，网页服务 PID $($web.Id)（http://127.0.0.1:$Port/），日志在 $Logs"
