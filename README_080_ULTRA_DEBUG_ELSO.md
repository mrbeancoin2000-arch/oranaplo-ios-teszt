# ÓraNapló 0.8.0 – teljes projekt + ULTRA DEBUG

**Alap:** a valóban meglévő `OraNaplo_071_SWIFT_LANGUAGE_JAVITOTT_TELJES.zip` (216 korábbi fájl), kiegészítve a mostani kiadással. Nem egy új, korábbit felülíró prototípus. Megőrzi a Google Sheets, HealthKit, éves Pro, Apple Watch, 100m futás, alvás/HRV, PDF, HU/EN/DE, víz/gyógyszer napló, felhasználói dashboard és ranglista forrását.

## 1. Windows – gyors indítás

- Csomagold ki külön mappába. **A régi 0.7.1-et és a telefon helyi adatait ne töröld!**
- Dupla kattintás: **`07_ULTRA_DEBUG.bat`**. Biztonságos offline audit, Python + Swift + Node tesztek; logok `logs/ULTRA_DEBUG_*/REPORT.html`, `REPORT.json`, naplófájlok.
- Teljes korábbi Windows-automata folyamat: **`00_MINDENT_INDIT.bat`**. Ez az offline diagnosztikát is futtatja, utána továbbra is GitHub Actions-alapú macOS IPA-buildet kezdeményez. Szükség van a korábban beállított GitHub hozzáférésre.
- Legfrissebb buildhez az **`.github/workflows/ultra-debug-macos-080.yml`** GitHub Actionst is indítsd (Actions → `ÓraNapló 0.8 Mac SDK full diagnostic` → Run workflow). Ezzel külön iOS Simulator, watchOS Simulator és iOS device SDK fordítási naplót, `.xcresult` fájlokat kapsz. Nem aláírt végleges IPA.
- A hibákhoz add át a `REPORT.json`, az érintett `.log` fájlokat, illetve szükség esetén a GitHub `.xcresult` mappáit. Soha ne add át a Google/Supabase privát tokeneket, Apple p8 kulcsot, GPS nyomvonalat vagy nyers HealthKit exportot.

## 2. Mi új?

- Biztonságos, lokális, korlátos **strukturált diagnosztika**: iPhone: app indítás, háttérfeladat, HealthKit engedély, szinkron, sorhelyreállítás, Watch kapcsolat, GPS edzés, StoreKit termék, vásárlás, referral. Watch: edzés/kapcsolódás események. A log csak kategória, előre megadott eseménykód, súlyosság, időpont, opcionális műveleti darabszám/időtartam; NEM tartalmazhat nyers adatot/tokent. A Profil → Diagnosztika alatt másolható és törölhető.
- **`supabase/03_referrals.sql`**: első regisztráció, saját kód, egy meghívott/egy meghívó jutalom, láncszabály (csak a meghívott kedvezményes évének lejárta után új meghívás), egyszeri StoreKit-ajánlatkód kiosztás; DB unique + RLS.
- **Sign in with Apple / Supabase** meghívási kliens, külön Apple ajánlatkód felület; a kedvezményes vásárlás **alapértelmezetten letiltva**, mert valódi App Store Connect ajánlatok, a végleges 500 Ft árpont, a JWS-vásárlás hitelesítése és éles anti-abuse még nincs tesztelve. Az egyéb Pro funkciók továbbra is StoreKit 2 verified transaction alapján működnek.
- **151 örökölt teszt + 17 új 0.8 teszt**; diagnosztikai JSON/HTML, SHA256 manifest és külön hibanaplók.

## 3. Korlátok – nem hamisítunk eredményt

- Az offline audit **nem képes igazolni** a teljes Xcode Apple SDK-fordítást Linux/Windows alatt. Ezt csak valódi macOS runner végzi. A 0.8 Mac Actions workflow-t még le kell futtatni.
- Az Apple Watch aláírt telepítése, HealthKit háttér-életciklusa, iPhone WatchConnectivity, 7 napos adatmentés, valós Sheets OAuth, éles StoreKit/Offer Code és teljes GDPR/App Privacy továbbra is bizonyítandó.
- **Az éles terjesztés FAIL-CLOSED / BLOCKED**; ezt automatikus ellenőrzésben és `release_manifest.json` mezőkben is jelöljük. A weboldal-sablonok és widgetek a korábbi állapotúak; widget target és App Group aláírás még nem megvalósított.
- A teljes diagnosztikai naplózás sem jelent folytonos HealthKit-adatmérést. Az iOS háttérfutás opportunisztikus; a részletes mérési értékeket nem írjuk a logba. A meglévő funkciókhoz tartozó üzemi adatokat külön, jogosultság alapján kezeljük.
- Nem szabad a `ReferralService.publicOffersEnabled` kapcsolót `true`-ra állítani, amíg az Apple JWS-verifikációs szerver, Apple ajánlatkészlet, visszatérítés-kezelés és éles tesztek el nem készültek.

## 4. Élesítés előtti következő blokkolók

1. Mac SDK build lefut: `xcodebuild-iphone-simulator.log`, `xcodebuild-watch-simulator.log`, `xcodebuild-iphone-device.log` mind OK.
2. Apple Developer regisztráció, bundle ID/HealthKit/Sign in with Apple entitlements és Watch companion aláírás valós iPhone + Watch páron.
3. StoreKit éves Pro SKU és 500 Ft-os magyar offer árpont ellenőrzése App Store Connectben, sandbox fizetés.
4. App Store Server Notifications V2 Apple-signed JWS ellenőrző Supabase szerver, biztonságos `appAccountToken` összekapcsolás, szabályok visszatérítésre, DeviceCheck/App Attest.
5. Google OAuth és Sheets-szinkron, 100 méteres futás, alvás, HRV, háttérszinkron, Watch offline ACK éles készülékes tesztje.
6. App Store jogi oldal, adatvédelmi válaszok és előfizetési feltételek véglegesítése.

A `logs/` helyileg létrehozott privát futási fájlokat tartalmazhat, GitHubra nem kerülnek és a ZIP-hez csak tisztított mintajelentés csatolt. A Safe diagnostics logokat a felhasználó csak külön gombnyomással másolhatja.
