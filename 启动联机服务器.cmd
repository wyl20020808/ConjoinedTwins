@echo off
setlocal
set "ENGINE=D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
if not exist "%ENGINE%" (
  echo Godot executable missing: %ENGINE%
  pause
  exit /b 1
)
rem Online relay server, no window. Default UDP port 24680. Custom port: append -- --port=NNNNN
"%ENGINE%" --headless --path "%~dp0." res://scenes/net_relay.tscn %*
pause
