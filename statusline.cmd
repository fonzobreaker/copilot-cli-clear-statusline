@echo off
chcp 65001 >nul
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.copilot\statusline.ps1"
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.copilot\statusline.ps1"
)
