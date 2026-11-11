# ÓraNapló 0.5.6 – ÖT TELJESEN ÁTTERVEZETT FŐOLDAL

**Ezzel kezdj:** `00_MINDENT_INDIT.bat`. A korábbi 0.5.5 projekt minden fájlja megmaradt, a forrás a kért öt főoldalra lett átalakítva.

## Képernyők

**Ma** – nagy lépésgyűrű, aktív kcal, táv, mozgásidő; előző éjszaka alvásidőtartama, sáv és összevetés korábbi alvásokkal; mai átlag/min/max pulzus. Az értékek Apple Healthből olvasott tényleges adatok, hiány esetén „—”. A bemutatott összehasonlítás alvásidőt, nem orvosi értelemben vett alvásminőséget értékel.

**Elemzés** – az aktuális telepítés első rögzített használata óta eltelt napok, Google Sheets ténylegesen kitöltött sorainak száma, Sheet-megnyitás, szinkron állapot. A nagy táblázat sorainak megszámlálása időbe telhet.

**Futás** – Apple MapKit előnézeti térkép helymeghatározási engedéllyel; indítás, szüneteltetés, folytatás, leállítás; táv, idő, tempó, sebesség, becsült kcal, Core Motion lépések, 100 méteres szakaszok, helyi futáselőzmény, GPX és névvel ellátott térképes megosztókártya. Élő Watch pulzus a korábbi kísérőprojektben, egyelőre nem igazolt valódi eszközökön.

**Ranglista** – összes lépés az app regisztrált használata óta és a leghosszabb egyszeri GPS-futás; TOP 50 valós, opt-in résztvevő és saját helyezés. A publikus ranglistához külön Supabase projekt kell (SQL + beállítások csatolva). Alapból ki van kapcsolva; nincs fiktív adat, és nem hitelesített csalásbiztos verseny.

**Profil** – Google bejelentkezés és leválasztás, HealthKit hozzáférés kérése, nyilvános megjelenített név, szerveres ranglistára külön közzététel/eltávolítás, GPS-alapú személyes rekordok, régi részletes egészségprofil, napló, beállítások (három nyelv, Pro, diagnosztika). Az új név a megosztott futáskártyán is megjelenik.

## Beállítások és ellenőrzés

1. Csomagold ki a teljes ZIP-et új mappába, ne keverd a régi verzióval.
2. **Csak** a `00_MINDENT_INDIT.bat` fájlt futtasd. A Windows-előkészítés és a helyi tesztek után a GitHub-feltöltést külön jóvá kell hagynod.
3. A GitHub Actions macOS ellenőrizni fogja a valódi Apple SDK-s SwiftUI-típusfordítást. A helyi `swiftc -frontend -parse` **nem** helyettesíti az Xcode-ot.
4. Ranglista bekapcsolása: `supabase/README_HU.md` és `supabase/01_leaderboard.sql`, valamint `ios/Resources/leaderboard_config.json`. A publikus kulcs megosztható, a *service role* kulcsot tilos a projektbe helyezni.
5. Béta/éles: Apple Developer HealthKit-aláírás, iPhone GPS/Watch teszt, Google OAuth élesítés, Apple StoreKit teszt és App Store Review.

**Ingyenes csomag:** a telefonon a napi értékek olvashatók az Apple Health engedélyével, a saját Google Sheetsbe továbbra is kizárólag a pulzusminták exportálhatók. **Pro, 1 000 Ft/év irányár:** teljes részletes export és elemzések, ha az App Store Connectben valódi termék létezik és ellenőrzött StoreKit vásárlás történt.

**Adatvédelem:** más felhasználók sem Google Sheethez, sem teljes egészségadatokhoz nem férnek hozzá. A Supabase ranglistára a felhasználó külön közzétesz három összesített adatot (név, lépés, leghosszabb futás) és bármikor törölheti a bejegyzést, amennyiben online elérhető a szerver. A weboldali adatkezelési nyilatkozatot éles publikálás előtt a Supabase szolgáltatással frissíteni kell.

**Helyi ellenőrzések:** a `tools/prepayment_audit.py` JSON/HTML riportot és nyers naplókat ment a `logs/prepayment_*` mappába. Az Xcode-fordítás és a valódi iPhone/Watch-környezet itt nem igazolható.
