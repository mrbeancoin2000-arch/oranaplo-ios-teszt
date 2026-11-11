# ÓraNapló 0.5.2 – egygombos Windows-folyamat

## Használat

**Csak a `00_MINDENT_INDIT.bat` fájlt indítsd el.** A program ebben a sorrendben végzi a lépéseket:

1. `01_WINDOWS_ELOKESZITES.bat`: Python/Git/GitHub CLI ellenőrzés, Google OAuth forráskonfiguráció, 71 Python-teszt. Napló: `logs/setup_*.log`.
2. `05_FIZETES_ELOTTI_TESZTEK.bat`: részletes helyi audit, külön HTML/JSON és nyers naplók a `logs/prepayment_*` mappában. Ha nincs Swift-fordító Windows alatt, annak eredménye őszintén *SKIPPED*, nem PASS.
3. `02_FELHOS_IPA_EPITES.bat`: GitHub-bejelentkezés, **külön jóváhagyással** publikus forrásfeltöltés, a `macos-ipa.yml` felhőbeli munkafolyamat elindítása. Ugyanaz a workflow futtatja a Python/Swift teszteket, a valódi Apple SDK-s **szimulátorfordítást**, az iPhoneOS-fordítást, az IPA ellenőrzését és az artifactok letöltését. Kimenet: `output/OraNaplo-UNSIGNED.ipa`.
4. `03_SIDELOADLY_MEGNYITAS.bat`: megnyitja a letöltött IPA-t a Windows Intézőben, és – ha ismert helyen megtalálható – elindítja a Sideloadlyt, egyébként a hivatalos weboldalát.

Az `00_MINDENT_INDIT.bat` **nem áll meg felesleges PAUSE-nál** a részmunkafolyamatok közben. Egy feladat hibája megállítja a továbbiakat és leírja az elbukott szakaszt a `logs/MINDENT_INDIT_*.log` fájlba. A `01`–`05` BAT-ok önállóan is használhatók.

## Amit emberi jóváhagyás nélkül nem lehet automatizálni

- A GitHub hitelesítést és a **nyilvános forráskód-feltöltés jóváhagyását**. A `cloud_build.ps1` itt `IGEN` beírását kéri, privát tokeneket és `google_oauth.json` fájlt nem tölthet fel. A felhőben egy csak nyilvános OAuth-metaadatokat tartalmazó tesztpéldány épül újra, hogy az összes regressziós teszt lefuthasson.
- A Sideloadly Apple ID-val végzett iPhone-aláírását, az USB-telepítést és az Apple Egészség engedélykérését.
- Az **éles HealthKit-entitlementet**, a fizetős Apple Developer tagságot és az App Store-os StoreKit-előfizetést.

## A javított hiba

A korábbi `tools/configure.py` minden futtatáskor törölte a futásrögzítő `UIBackgroundModes/location` beállítását, és csak `fetch` maradt. Most megőrzi és biztonságosan hozzáadja a `fetch` + `location` módokat. A `tests/test_052_full_launcher.py` többszöri konfiguráció-futtatással is ellenőrzi, hogy ne jöjjön vissza a hiba. Az IPA-ellenőrző a háttérmódot is vizsgálja.

**Valódi iOS Xcode buildet csak a GitHub Actions eredménye bizonyítja**, nem a helyi tesztek. A tesztek zöld eredménye még nem jelent HealthKit-működést vagy App Store-készséget.

A Githubra feltöltött tesztprojekt tartalmazza a `scripts/Ertekeles.gs` offline Apps Script ellenőrzéshez szükséges fájlt is.
