@echo off
setlocal
set "ENGINE=D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
if not exist "%ENGINE%" (
  echo Godot executable missing: %ENGINE%
  pause
  exit /b 1
)
rem A trailing backslash before the closing quote breaks Godot argument parsing.
"%ENGINE%" --path "%~dp0." res://scenes/road_demo.tscn %*
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo Game failed to start. Exit code: %RESULT%
  pause
)
exit /b %RESULT%
