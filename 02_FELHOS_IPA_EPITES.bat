@echo off
setlocal
cd /d "%~dp0"
if not exist logs mkdir logs
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%a
set "LOG=logs\build_%STAMP%.log"
echo [OraNaplo] GitHub Actions macOS: nem alairt IPA keszitese
echo Naplo: %LOG%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\cloud_build.ps1" -LogPath "%CD%\%LOG%"
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (echo Epitesi hiba. A logs mappaban latod az uzeneteket. & pause & exit /b %ERR%)
pause
