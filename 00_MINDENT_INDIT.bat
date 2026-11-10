@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title OraNaplo - Windows teljes folyamat
color 1F
echo ================================================================
echo  ORANAPLO iOS PROTOTIPUS - WINDOWS INDITO
 echo ================================================================
echo  1. Windows fuggosegek telepitese es helyi teszt
 echo  2. Google OAuth konfiguracio ellenorzese
 echo  3. GitHub macOS IPA forditas es letoltes
 echo  4. Sideloadly telepitesi seged
 echo ================================================================
echo.
call "%~dp001_WINDOWS_ELOKESZITES.bat"
if errorlevel 1 goto :failed
if not exist "google_oauth.json" goto :oauth
powershell -NoProfile -Command "$c=Get-Content -Raw 'google_oauth.json' | ConvertFrom-Json; if ([string]::IsNullOrWhiteSpace($c.ios_client_id) -or $c.ios_client_id.StartsWith('ADD_')) {exit 2} else {exit 0}"
if errorlevel 1 goto :oauth
echo A Google OAuth Client ID megtalalva.
call "%~dp002_FELHOS_IPA_EPITES.bat"
if errorlevel 1 goto :failed
call "%~dp003_SIDELOADLY_MEGNYITAS.bat"
if errorlevel 1 goto :failed
echo Kesz. A Sideloadly kulon, manualis telepitest igenyel.
pause
exit /b 0
:oauth
echo.
echo HIANZIK A GOOGLE BEALLITAS.
echo Masold le a google_oauth.example.json-t google_oauth.json nev alatt,
echo majd allitsd be benne a sajat iOS OAuth Client ID-t.
echo Reszletes leiras: docs\GOOGLE_BEALLITAS.md
start "Google beallitas" "docs\GOOGLE_BEALLITAS.md"
echo A Google beallitas utan futtasd ujra ezt a BAT-ot.
pause
exit /b 3
:failed
echo.
echo A folyamat leallt. Nezd meg a logs mappat es a GitHub Actions fordítási naplojat.
pause
exit /b 1
