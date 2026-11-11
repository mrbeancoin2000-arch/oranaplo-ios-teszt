@echo off
setlocal
cd /d "%~dp0"
echo === OraNaplo 0.6.1 ingyenes helyi ellenorzes ===
where py >nul 2>&1
if %errorlevel%==0 (
  py -3 -m unittest discover -s tests -p "test_*.py" -q
) else (
  python -m unittest discover -s tests -p "test_*.py" -q
)
if errorlevel 1 (
  echo HIBA: A Python tesztek nem sikerultek. Ne lepjen tovabb!
  pause
  exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
  echo FIGYELEM: Node.js nincs telepitve. A 3 JS ellenorzes kimaradt.
) else (
  node --test tests/test_057_support_policy.mjs
  if errorlevel 1 (
    echo HIBA: A JS tesztek nem sikerultek.
    pause
    exit /b 1
  )
)
echo.
echo A Swift parser es Apple SDK build csak Apple buildkornyezetben tesztelheto.
echo A 15 kiadasi feltetel tovabbra is kulon, bizonyitekkal ellenorizendo.
echo A kovetkezo lepes: GitHub Actions - Prepayment audit + unsigned iOS simulator build.
pause
