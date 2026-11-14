@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
echo ============================================================
echo ORANAPLO 0.8 - ULTRA DEBUG / SAFE LOGGING / RELEASE GATES
echo ============================================================
where py >nul 2>nul
if not errorlevel 1 (
    py -3 "tools\ultra_debug.py"
) else (
    python "tools\ultra_debug.py"
)
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
    echo [ERROR] Offline checks failed. See logs\ULTRA_DEBUG_*\REPORT.html
    exit /b %CODE%
)
echo.
echo [OK] Local checks successful. App Store/device gates still BLOCKED.
echo Reports in logs\ULTRA_DEBUG_*\REPORT.html
exit /b 0
