@echo off
rem Start the web server (127.0.0.1:8080) and online relay in the background. Add -Publish to copy builds\web first, -Stop to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_server.ps1" %*
pause
