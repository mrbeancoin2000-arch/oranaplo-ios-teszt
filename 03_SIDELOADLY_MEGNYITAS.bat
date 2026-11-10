@echo off
setlocal
cd /d "%~dp0"
if not exist logs mkdir logs
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%a
set "LOG=logs\sideload_%STAMP%.log"
echo [OraNaplo] Sideloadly telepitesi seged > "%LOG%"
for /r "output" %%F in (*.ipa) do (
  echo IPA megtalalva: %%F >> "%LOG%"
  echo IPA megtalalva: %%F
  explorer.exe /select,"%%F"
  goto :found
)
echo Nincs IPA az output mappaban. Elobb futtasd a 02_FELHOS_IPA_EPITES.bat fajlt.
echo Nincs IPA az output mappaban. >> "%LOG%"
pause
exit /b 2
:found
start "Sideloadly" "https://sideloadly.io/"
echo Telepites: nyisd meg a Sideloadly programot, USB-n csatlakoztasd az iPhone-t, majd huzd bele az IPA-t.
echo A Sideloadly csak alairni/telepiteni segit; a HealthKit entitlement ingyenes Apple ID-val nem garantalt.
pause
