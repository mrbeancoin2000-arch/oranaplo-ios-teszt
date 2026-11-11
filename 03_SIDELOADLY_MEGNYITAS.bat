@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist logs mkdir logs
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set STAMP=%%a
set "LOG=logs\sideload_%STAMP%.log"
echo [OraNaplo] Sideloadly telepitesi seged > "%LOG%"
set "IPA=%CD%\output\OraNaplo-UNSIGNED.ipa"
if not exist "%IPA%" goto :noipa
for %%F in ("%IPA%") do if %%~zF EQU 0 goto :noipa
echo IPA: %IPA%
echo IPA: %IPA% >> "%LOG%"
explorer.exe /select,"%IPA%"
set "SIDELOADLY_EXE="
if exist "%ProgramFiles%\Sideloadly\Sideloadly.exe" set "SIDELOADLY_EXE=%ProgramFiles%\Sideloadly\Sideloadly.exe"
if exist "%ProgramFiles(x86)%\Sideloadly\Sideloadly.exe" set "SIDELOADLY_EXE=%ProgramFiles(x86)%\Sideloadly\Sideloadly.exe"
if exist "%LocalAppData%\Programs\Sideloadly\Sideloadly.exe" set "SIDELOADLY_EXE=%LocalAppData%\Programs\Sideloadly\Sideloadly.exe"
if defined SIDELOADLY_EXE goto :startinstalled
echo Sideloadly nem talalhato az ismert mappakban. Megnyitjuk a hivatalos oldalat.
start "" "https://sideloadly.io/"
goto :manual
:startinstalled
start "" "%SIDELOADLY_EXE%"
:manual
echo A telefon USB-csatlakoztatasa, Apple alairas es iPhone telepites manualis.
echo HealthKit entitlement Sideloadly utani megmaradasa NEM garantalt.
if not defined ORANAPLO_FROM_ALL pause
exit /b 0
:noipa
echo Nincs ellenorzott IPA: %IPA%
echo Nincs IPA: %IPA% >> "%LOG%"
if not defined ORANAPLO_FROM_ALL pause
exit /b 2
