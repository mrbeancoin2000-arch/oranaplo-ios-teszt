# ÓraNapló 0.6.1 – fizetés előtti minőségbiztosítás

**Nem publikálható kiadás.** A csomag a 0.6.0-ra épülő forráskód, lokálisan ellenőrizhető javítások és valódi készülékes tesztterv együttese.

**A legfontosabb:** [Részletes tesztelés](docs/ORA_NAPLO_061_TELJES_TESZTELES.md), [Kiadáskapuk állapota](docs/QA_061/QA_STATUS.json), [7 napos napló](docs/QA_061/NAPI_SZINKRON_NAPLO.csv).

### Új technikai változtatások

- **Lejáró Pro:** a még fel nem töltött HRV-edzés/napló adatok nem vesznek el csak azért, mert a Pro lejárt; a feltöltési csomag Free módban csak pulzusrekordokat enged ki.
- **Kihagyott/dupla sor elleni védelem:** a távoli Google Sheets ID oszlop ellenőrzésének helyi egyeztetési állapota konkrét spreadsheethez kötött; uncertain upload után távoli egyeztetés történik.
- **Nagy HealthKit import:** 30 000 mintánkénti felső határ nem rejtett siker, hanem kifejezett hiba/folytatási pont.
- **Watch:** elkészült edzés után a Watch összesítését az elérhetőségtől független `transferUserInfo` sorba teszi, aktiválás után továbbítja; iPhone oldalon UUID szerinti ismétlésvédelem. A Watchon még nincs önálló nyers GPS-track átküldés.
- **CI:** `project.watch.yml` alapján kötelező iOS és watchOS szimulátoros build; az aláíratlan IPA ellenőrzője már elvárja a beágyazott Watch appot.
- **Három nyelvű szinkronállapotok:** 35 előfordulásnyi státuszüzenet és 3 kapcsolódó üzenet HU/EN/DE változata elkészült. Statikus figyelmeztetésszám: 0; a teljes UI eszközös nyelvi ellenőrzése továbbra is kötelező.
- **Tesztelés:** külön QA állapottábla, hét nap két ellenőrzés/nap napló, valódi Supabase RLS-tesztprogram két ideiglenes anonymous Auth-userrel.

### Rövid teendők

1. Készíts teljes mentést a 0.6.0-ról; új mappába csomagold ezt ki.
2. Windowson dupla kattintás: **`06_INGYENES_HELYI_TESZTEK.bat`**, vagy manuálisan: `python -m unittest discover -s tests -p "test_*.py" -q` és `node --test tests/test_057_support_policy.mjs`.
3. GitHub Actions -> `Prepayment audit + unsigned iOS simulator build` -> Run workflow. Két `xcodebuild*.log`-ban keresd a hiba pontos helyét.
4. A sikeres Apple SDK build **után** végezd el a 15 QA-ellenőrzést a részletes útmutató szerint.
5. App Store, Sandbox és 20 külső TestFlight-tesztelő csak a Developer tagság után.

### Ismert korlátok

A telepítéshez, valós HealthKit-hez, Watch kapcsolat tesztjéhez és StoreKit helyi próbájához Xcode + megfelelő aláírás és/vagy párosított eszköz szükséges; Windows önmagában nem elegendő. A GitHub Actions unsigned build nem telepíthető egyenesen App Store-ként. A 7 napos időtartam és a 20 tesztelő nem igazolható most. Az alkalmazás pulzusadat-értelmezése nem orvosi diagnózis.
