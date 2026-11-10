@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist logs mkdir logs
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%a
set "LOG=logs\setup_%STAMP%.log"
echo [OraNaplo] Windows eszkozok telepitese / ellenorzese
echo A reszletes naplo itt lesz: %LOG%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows_setup.ps1" -LogPath "%CD%\%LOG%"
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" (echo A beallitas hibaval zart. Kuldd el a fenti naplot. & pause & exit /b %ERR%)
echo A helyi ellenorzes befejezodott. Ez NEM keszitett iOS IPA fajlt.
pause
