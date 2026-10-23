@echo off
setlocal
set "GAME_ROOT=%~dp0"
if not exist "%GAME_ROOT%build-tools\play_boss.gd" set "GAME_ROOT=D:\ConjoinedTwins-task-temp\boss-launchers\"
set "GODOT=D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot executable missing.
  pause
  exit /b 1
)
echo Preparing Boss scene assets...
"%GODOT%" --headless --path "%GAME_ROOT%." --editor --import
if errorlevel 1 (
  pause
  exit /b 1
)
"%GODOT%" --path "%GAME_ROOT%." --resolution 1600x900 --script res://build-tools/play_boss.gd -- 1
if errorlevel 1 pause
