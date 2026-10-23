@echo off
setlocal
set "ANIMATION_GODOT=D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64.exe"
if defined GODOT_BIN set "ANIMATION_GODOT=%GODOT_BIN%"
if not exist "%ANIMATION_GODOT%" (
  echo Godot not found. Set GODOT_BIN to your Godot executable.
  pause
  exit /b 1
)
start "" "%ANIMATION_GODOT%" --path "%~dp0." res://scenes/combat_trial.tscn
