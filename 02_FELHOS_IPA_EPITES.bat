@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist logs mkdir logs
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%a
set "LOG=logs\build_%STAMP%.log"
echo [OraNaplo] Github macOS - valodi Swift, iOS simulator, unsigned IPA
echo Reszletes naplo: %LOG%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\cloud_build.ps1" -LogPath "%CD%\%LOG%"
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" echo HIBA: Github Actions. A reszletek a %LOG% es output\diagnostics-* mappakban.
if "%ERR%"=="0" echo Sikeres felhoepites. Az IPA az output mappaban van.
if not defined ORANAPLO_FROM_ALL pause
exit /b %ERR%
