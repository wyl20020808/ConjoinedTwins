@echo off
cd /d "%~dp0"
"D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64.exe" --path "%~dp0." --resolution 1600x900 --script res://build-tools/boss/play_finale.gd
