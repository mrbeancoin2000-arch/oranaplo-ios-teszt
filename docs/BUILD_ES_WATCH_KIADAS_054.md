# ÓraNapló 0.5.4 – Valódi kiadási kapuk

## A 2026. november 11-i CI-bukás elemzése
A korábbi run `43014354741` a GitHub macOS iOS-szimulátoros fordításánál állt le, `SwiftCompile failed with a nonzero exit code` állapottal. A beküldött Windows-logból NEM derült ki, melyik Swift-fájl hányadik sorában volt a tényleges fordítói `error:`. A 79 helyi Python-teszt eredménye ezért nem bizonyította az Apple SDK-s fordíthatóságot.

Az új `tools/ci_xcode_build.sh` 20 másodpercenként kiírja a futás állapotát, részletes teljes Xcode-naplót ment, és hiba esetén a konkrét `error:` sorokat kiemeli. Windows alatt a `tools/cloud_build.ps1` az új runhoz tartozó naplót letölti és szűri. Ha ismét sikertelen, küldendő: `output/build-logs-<RUN_ID>/xcodebuild-simulator.log`, és ha van `xcodebuild-watchsimulator.log`. Ne a hibát összefoglaló utolsó 50 sor alapján diagnosztizáljunk.

## 0.5.4 további funkciói
- A watchOS-forrás külön Watch targetben elindítja, szünetelteti és befejezi az órás HealthKit-edzést, és élő pulzust/távot olvas, ha az Apple hozzáférést megadta.
- Az iPhone-oldali WatchConnectivity üzenetek csak akkor kézbesíthetők, ha a kapcsolat és az iOS végrehajtás lehetővé teszik. Az órával indított futás nem garantál iPhone-os GPS-útvonalat, ha a telefon app nincs futásban.
- Aktív futás esetén iPhone Core Location háttérmód és távolság-alapú GPS frissítés, szünetnél leállítás, újrakezdésnél új szakasz. Tényleges hosszú futás, iOS energiatakarékos mód és lezárt telefon tesztje NEM történt meg.
- 1/5/10 km és 21,097 km GPS-szakasz alapú PR, heti/havi futáscél és egymást követő sikeres hetek. A PR és cél adatokat route-mentes archívum tartja meg a 25 helyi részletes GPS-track forgatásán túl.
- Google Sheets: Dashboard formázás, számított futótáv/százméteres sebesség/pulzuseloszlás, diagramok, Rekordok és Celok lapok. Az értékek Google API-val történő képlet-kiértékelése külön élő fiókos tesztet igényel.
- Térképes sötét futáskártya helyben, külön felhasználói megosztási gombbal. A lakcímet felfedő GPS-útvonalat ne osszuk meg gondolkodás nélkül.

## Pontos készenléti állapot
- **Sikeresen ellenőrizve ezen a Linux gépen:** 90 Python-teszt, Apps Script offline, Swift szintaxis, több Swift futtatott alapalgoritmus, PR/cél tesztek, kiadás előtti metaadatellenőrzés és a kiadás kapujának elvárt elutasítása.
- **Még nem ellenőrzött:** iOS iPhone/szimulátor valós Xcode compile, Watch app target compile és watchOS telepítés, Apple HealthKit aláírás és tényleges pulzus, lezárt telefonos GPS, valódi Google Sheets chart API és StoreKit előfizetés.
- **Fontos:** `project.yml` csak iPhone-t tartalmaz, `project.watch.yml` a Watch célt is. Az IPA-ba Watch app még **nem** kerül be. Egy külön CI-lépés megpróbálja a watchOS compile-ot, de ez nem blokkolja az iPhone IPA előállítását. Éles forgalmazás előtt a Watch cél beágyazását, aláírását és eszközös tesztjét el kell végezni.
- **Adatvédelem:** nincs külön ÓraNapló egészségadat-szerver. A Google OAuth / Sheets saját Google-fiókot használ; a Google/Apple rendszereknek továbbra is vannak saját szabályai. A teljes GPS-track nem megy automatikusan Sheetsbe, a megosztás kézi.
