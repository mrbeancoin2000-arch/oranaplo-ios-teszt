@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist logs mkdir logs
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%a
set "LOG=logs\setup_%STAMP%.log"
echo [OraNaplo] Windows eszkozok telepitese / ellenorzese
echo Reszletes naplo: %LOG%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows_setup.ps1" -LogPath "%CD%\%LOG%"
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" echo HIBA: Windows setup, hibakod %ERR%. Naplo: %LOG%
if "%ERR%"=="0" echo A Windows helyi ellenorzes sikeres. Az iOS IPA a felhoben keszul.
if not defined ORANAPLO_FROM_ALL pause
exit /b %ERR%
