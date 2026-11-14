# ÓraNapló 0.8.2 – Apple SDK fordítási hibajavítás

**Bizonyított kiinduló hiba:** GitHub Actions run `43591225229`, iOS Simulator xcodebuild (exit 65):
`ios/Sources/DiagnosticCenter.swift:79:84: error: type 'OSLogType' has no member 'notice'`.

**Javítás:** a `DiagnosticCenter.record` `OSLogType.notice` értékét `.default` értékre
cseréltük. Az Apple `OSLogType` típus támogatott értékei között `.default`, `.info`,
`.debug`, `.error`, `.fault` található. A figyelmeztetés naplózása megmarad.

**Verzió:** iPhone- és Watch-alkalmazás `0.8.2`, build `22`. Az üzleti logikát,
a HealthKit működését, a StoreKit árakat és a Supabase séma fájljait
**nem változtattuk meg** ezzel a fordítási hibajavítással.

**Új tesztek:** `tests/test_082_oslog_sdk_compat.py` három forrásoldali regressziós ellenőrzést ad.
Ezek nem helyettesítik a GitHub macOS Xcode SDK fordítást.

## Futtatás Windows rendszeren

1. Csomagold ki a teljes 0.8.2 ZIP-et új mappába; ne írd bele a korábbi hibás mappába.
2. A saját `google_oauth.json` fájlodat másold a projekt főmappájába, a `.bat` fájlok mellé.
3. Futtasd a `07_ULTRA_DEBUG.bat` fájlt a helyi ellenőrzéshez.
4. Indítsd el a `00_MINDENT_INDIT.bat` fájlt a **következő** GitHub macOS build indításához.
5. Ha az Xcode új hibát jelez, a `logs/build_*.log` és az `output/build-logs-<runid>/`
   mappa naplóiból küldd el a pontos hibaüzenetet.

**Óvatosság:** a korábbi `ipa-diagnostics` artefaktum hiányára vonatkozó üzenet
másodlagos következmény volt, mert a Simulator-fordítás már előbb leállt.
A GitHub Node.js 20 figyelmeztetés szintén nem ez a Swift hiba.

**Kiadási korlát:** Az új ZIP itt nem futott le Apple SDK-n és valódi készüléken.
Az App Store, Watch HealthKit és előfizetés-jóváhagyás előtti blokkoló
ellenőrzések maradjanak aktívak. A felhasználó antivírusában megjelent két
észlelés fájlneve/eredete a képernyőképből nem állapítható meg; a karantént
külön ellenőrizni kell. Ne tiltsd le a vírusvédelmet a build kedvéért.
