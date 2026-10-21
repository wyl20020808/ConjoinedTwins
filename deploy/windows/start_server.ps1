<#
Windows 本机发布网页版：网页服务（127.0.0.1:8080）+ 联机中继（UDP 24680 / WebSocket 24681），后台无窗口运行。
SakuraFrp TCP 隧道（开启自动 HTTPS）把公网地址转到 127.0.0.1:8080，队友打开隧道地址即可游玩和联机。

用法（PowerShell，在工程根目录）：
  powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1 -Publish   # 先把 builds\web 复制到站点目录再启动
  powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1            # 只（重新）启动服务
  powershell -ExecutionPolicy Bypass -File deploy\windows\start_server.ps1 -Stop      # 停止本脚本启动的服务

中继直接运行站点里的主包（--main-pack），保证联机协议与正在发布的网页版本一致。
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

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$relay = Start-Process -FilePath $Engine -WindowStyle Hidden -PassThru `
	-ArgumentList @("--headless", "--main-pack", "`"$(Join-Path $Site 'index.pck')`"", "res://scenes/net_relay.tscn") `
	-RedirectStandardOutput (Join-Path $Logs "relay-$stamp.log") -RedirectStandardError (Join-Path $Logs "relay-$stamp.err.log")
Set-Content (Join-Path $State "relay.pid") $relay.Id
$web = Start-Process -FilePath $Python -WindowStyle Hidden -PassThru `
	-ArgumentList @("-u", "`"$(Join-Path $PSScriptRoot 'serve_web.py')`"", "--root", "`"$Site`"", "--port", $Port) `
	-RedirectStandardOutput (Join-Path $Logs "web-$stamp.log") -RedirectStandardError (Join-Path $Logs "web-$stamp.err.log")
Set-Content (Join-Path $State "web.pid") $web.Id
Write-Output "联机中继 PID $($relay.Id)，网页服务 PID $($web.Id)（http://127.0.0.1:$Port/），日志在 $Logs"
