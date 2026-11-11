@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
echo OraNaplo 0.5.2 - Fizetes elotti teljes offline tesztcsomag
where py >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  py -3 tools\prepayment_audit.py
) else (
  python tools\prepayment_audit.py
)
set "STATUS=%ERRORLEVEL%"
echo.
echo Reszletes naplok: logs\prepayment_...\RESULT.json es JELENTES.html
if "%STATUS%"=="0" echo A helyi tesztek sikeresek; felho Xcode build es HealthKit teszt kulon szukseges.
if not "%STATUS%"=="0" echo HIBA: Nem minden helyi teszt sikeres; nezd a RESULT.json fajlt.
if not defined ORANAPLO_FROM_ALL pause
exit /b %STATUS%
