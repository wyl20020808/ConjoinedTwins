@echo off
setlocal
python -X utf8 "%~dp0build-tools\obstacle-expansion-6377e8b8\t05\validate.py"
exit /b %ERRORLEVEL%
