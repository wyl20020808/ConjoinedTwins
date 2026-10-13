@echo off
setlocal
set "ENGINE=D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64.exe"
if not exist "%ENGINE%" (
  echo Godot executable missing: %ENGINE%
  pause
  exit /b 1
)
rem Historical/debug whitebox only. Default game is Road Demo.
"%ENGINE%" --path "%~dp0." res://scenes/main.tscn
endlocal
