@echo off
setlocal
python "%~dp0build-tools\short-rope-t06\run_regressions.py" %*
if errorlevel 1 exit /b 1
python "%~dp0build-tools\short-rope-t06\audit_evidence.py"
exit /b %ERRORLEVEL%
