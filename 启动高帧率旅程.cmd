@echo off
cd /d "%~dp0"
python "%~dp0build-tools\run_high_fps.py" %*
if errorlevel 1 pause
