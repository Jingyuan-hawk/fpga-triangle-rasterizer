@echo off
rem Run this project's PowerShell receiver without changing system policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture_frame.ps1" %*
exit /b %ERRORLEVEL%
