@echo off
setlocal
"D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path "%~dp0." --script res://tests/headless.gd
set "RESULT=%ERRORLEVEL%"
echo Verification exit code: %RESULT%
pause
exit /b %RESULT%
