# ÓraNapló 0.5.0 – fizetés előtti kiadásjelölt

**Ez a teljes, módosítható iOS + Windows + GitHub Actions projekt.** Az Apple Developer-tagság és az éles App Store-beküldés még NINCS elvégezve.

## Első indítás Windows alatt

1. A teljes mappát csomagold ki egy új helyre. Ne csak a javított fájlokat másold a régi változatra.
2. Kattints a `05_FIZETES_ELOTTI_TESZTEK.bat` fájlra. Az eredmények a `logs/prepayment_.../RESULT.json`, `JELENTES.html` és külön `*.log` fájlokba kerülnek.
3. Futtasd a `01_WINDOWS_ELOKESZITES.bat` fájlt. Ez telepítheti az eszközöket, ellenőrzi a Google-beállításokat, és újragenerálja a konfigurációt.
4. Futtasd a `02_FELHOS_IPA_EPITES.bat` fájlt a korábbi, aláíratlan teszt-IPA-hoz.
5. A GitHub → Actions felületen külön indítsd: **Prepayment audit + unsigned iOS simulator build**. A zöld Xcode-build naplóját töltsd le. A Windows-teszt önmagában nem helyettesíti ezt.
6. Az aláíratlan teszt-IPA-t csak szükség esetén telepítsd Sideloadly-val. A HealthKit-jogosultság ennél hiányozhat.

## Mit ad hozzá a 0.5.0?

- Fájlokból kiválasztható, adagokban feldolgozott Apple Egészség `export.xml` import **HealthKit-jogosultság nélkül**. Az Apple Egészség exportált ZIP-jét előbb ki kell csomagolni; az alkalmazás `export.xml` fájlt kér. Ingyenes fiókkal csak pulzus, Pro-val a kiválasztott támogatott típusok. Az elérhetetlen vagy nem támogatott egységeket nem alakítja át kitalált értékekké.
- Külön, valós Swift-kóddal tesztelt 100 méteres GPS-/pulzus-algoritmus; pontatlan és túl gyors, ugró GPS-pontok kizárása. A kézi Apple Egészség XML-export nem tartalmazza az edzés teljes GPS-útvonalát, így a 100 méteres elemzés továbbra is HealthKit-útvonalat igényel.
- Google Sheets-feltöltés bizonytalan eredményének tartós jelölése és utólagos ellenőrzése, mielőtt újraküldené a sort; a nem idempotens append-hívás nem próbálkozik vakon újra.
- A már feltöltött azonosítók append-only naplója, hogy többéves importnál ne írja újra minden köteg után az egész azonosítólistát.
- HealthKit observer-kód és a hozzá szükséges background-delivery entitlement **előkészítve**; az Apple-aláírás és az eszközteszt hiányzik.
- Háromnyelvű XML-fájlimport képernyő és helyi, korlátozott műszaki eseménynapló.
- `tests/storekit/OraNaplo_Annual_Offline.storekit`: évi Pro **helyi teszttermék**, éles pénzt nem von le, nem helyettesíti az App Store Connectben létrehozandó terméket.
- Windows tesztindító és GitHub macOS CI, részletes géppel olvasható jelentéssel, HTML-lel, tesztnaplókkal.

## A tesztek pontos jelentése

A sikeres Python-tesztek között **forráskód- és konfigurációs ellenőrzések is vannak**. A Swift futásidejű tesztek a valódi `HealthXMLCore.swift` és `SplitMath.swift` modulokat hajtják végre, szintetikus adatokkal. Az Apps Script szabályait szimulált Google Sheets-munkalapokon futtatjuk. A GitHub CI következő lépése a valódi Apple SDK-s szimulátorfordítás, amit ezen a gépen nem tudtunk elvégezni.

**Nem igazolt jelenleg:** aláírt iPhone-os HealthKit-hozzáférés; az iOS háttérfutás megbízhatósága; valós Google-fiókos teljes Sheets-visszaállítás; StoreKit Sandbox-vásárlás; 1 000 Ft-os App Store Connect-termék; Apple- és Google-jóváhagyás; éles adatvédelmi oldal. A `release_manifest.json` ezért ezeknél `false`.

Részletes menet: `docs/FIZETES_ELOTTI_TELJES_UTMUTATO_050.md` és `docs/FIZETES_UTANI_TEENDOK_050.md`.
