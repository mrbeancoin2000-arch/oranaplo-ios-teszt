# ÓraNapló – GitHub-tárolóhiba javítása (2026-11-10)

## A naplók alapján

- Git/Python/GitHub CLI: OK.
- A helyi 5 Python-teszt: OK (nem valódi iOS-fordítás).
- Google OAuth Client ID: konfigurálva.
- GitHub-bejelentkezés: sikeres.
- A leállás oka: a `gh repo view` a még nem létező `oranaplo-ios-teszt` tárolónál hibakimenetet adott; Windows PowerShell 5.1-ben a globális `$ErrorActionPreference = 'Stop'` ezt megszakította, ezért a tároló létrehozása nem indult el.

## Javítások

1. `tools/cloud_build.ps1`: a hiányzó GitHub-repo többé nem állítja le a folyamatot; a hozzájárulás után megpróbálja létrehozni.
2. `.github/workflows/macos-ipa.yml`: nem írja felül a Windowson beállított Google OAuth kliensazonosítót a demókonfigurációval.
3. `.gitignore`: a felhasználó `google_oauth.json` fájlja helyben marad; a szükséges generált alkalmazáskonfiguráció kerül a forrásba.
4. `cloud_build.ps1`: ha létezik a GitHub-repo, biztosítja az `origin` remote helyes címét.

## Használat – a meglévő Windows mappában

**A legegyszerűbb:** másold át a JAVITAS_CSEREFAJLOK.zip tartalmát a meglévő `OraNaplo-iOS-Windows` mappába (felülírás engedélyezése), majd futtasd a `02_FELHOS_IPA_EPITES.bat` fájlt.

**Fontos:** ne töröld az eredeti `google_oauth.json` fájlodat, mert abban van a már beállított iOS Client ID. A teljes javított ZIP-ből is kicsomagolhatod a projektet új mappába, de abban a fájlban meg kell adnod a Google Client ID-t.

A GitHub-tároló nyilvános lesz; **ne tölts fel titkos tokeneket, jelszavakat vagy valódi egészségügyi adatokat**. Az OAuth Client ID önmagában nem titkos adat.

## Ha továbbra is hiba van

Küldd el a friss `logs/build_*.log` állományt. Ha a GitHub Actions már elindul, az Xcode-fordítás tényleges hibáihoz a GitHub `Actions` oldal `build-logs/xcodebuild.log` fájlja szükséges. A forráskódot macOS-es fordítóval és iPhone-on még nem ellenőriztük.
