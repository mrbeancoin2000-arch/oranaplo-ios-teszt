@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title OraNaplo 0.5.3 - MINDEN EGY INDITASSAL
color 1F
set "ORANAPLO_FROM_ALL=1"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
if not exist "logs" mkdir "logs"
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
if not defined STAMP set "STAMP=manual_%RANDOM%"
set "RUNLOG=%CD%\logs\MINDENT_INDIT_%STAMP%.log"
set "STAGE=inditas"
echo OraNaplo 0.5.3 - teljes egygombos folyamat > "!RUNLOG!"
echo Log: !RUNLOG!
echo ==============================================================
echo ORANAPLO - EGYGOMBOS WINDOWS ELLENORZES + iOS IPA BUILD
echo ==============================================================
echo [1/4] Windows eszkozok, Google konfiguracio, Python tesztek
echo [2/4] Reszletes fizetes elotti tesztek, naplok, riport
echo [3/4] GitHub macOS Swift + szimulator + iOS build, IPA letoltes
echo [4/4] Letoltott IPA es telepitesi seged megnyitasa
echo.
echo Megjegyzes: GitHub engedely, bejelentkezes es az iPhone >> "!RUNLOG!"
echo Sideloadly alairas/telepites szemelyes jovahagyast igenyel. >> "!RUNLOG!"
echo.
set "STAGE=01_WINDOWS_ELOKESZITES"
echo [%date% %time%] Indul !STAGE! >> "!RUNLOG!"
call "%~dp001_WINDOWS_ELOKESZITES.bat"
if errorlevel 1 goto :failed
echo [%date% %time%] OK !STAGE! >> "!RUNLOG!"
set "STAGE=05_FIZETES_ELOTTI_TESZTEK"
echo [%date% %time%] Indul !STAGE! >> "!RUNLOG!"
call "%~dp005_FIZETES_ELOTTI_TESZTEK.bat"
if errorlevel 1 goto :failed
echo [%date% %time%] OK !STAGE! >> "!RUNLOG!"
set "STAGE=02_FELHOS_IPA_EPITES"
echo [%date% %time%] Indul !STAGE! >> "!RUNLOG!"
call "%~dp002_FELHOS_IPA_EPITES.bat"
if errorlevel 1 goto :failed
echo [%date% %time%] OK !STAGE! >> "!RUNLOG!"
set "STAGE=03_SIDELOADLY_MEGNYITAS"
echo [%date% %time%] Indul !STAGE! >> "!RUNLOG!"
call "%~dp003_SIDELOADLY_MEGNYITAS.bat"
if errorlevel 1 goto :failed
echo [%date% %time%] OK !STAGE! >> "!RUNLOG!"
echo.
echo ==============================================================
echo MINDEN AUTOMATIZALHATO LEPES SIKERES.
echo A HealthKit nem igazolt ingyenes Sideloadly alairassal.
echo A telefonos IPA alairashoz es telepiteshez kezi jovahagyas kell.
echo Naplok: logs\  ^|  IPA: output\OraNaplo-UNSIGNED.ipa
echo ==============================================================
echo [%date% %time%] MINDEN AUTOMATIZALHATO LEPES OK >> "!RUNLOG!"
echo Osszesito naplo: !RUNLOG!
pause
exit /b 0
:failed
set "CODE=!ERRORLEVEL!"
echo.
echo HIBA a !STAGE! szakaszban. Hibakod: !CODE!
echo Reszletes naplok: logs\ es a Github Actions / artifacts.
echo [%date% %time%] HIBA !STAGE! kod=!CODE! >> "!RUNLOG!"
echo Osszesito naplo: !RUNLOG!
pause
exit /b !CODE!
