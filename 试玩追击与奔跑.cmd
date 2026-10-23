@echo off
setlocal
set "ENGINE=D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
if not exist "%ENGINE%" (
  echo Godot executable missing: %ENGINE%
  pause
  exit /b 1
)
"%ENGINE%" --path "%~dp0." res://scenes/journey_boot.tscn
exit /b %ERRORLEVEL%
