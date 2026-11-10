# ÓraNapló – IPA konfiguráció-ellenőrzés hibajavítása

## Mit mutattak a naplók?

A **42882878547** futásban az Xcode/Swift fordítás (Unsigned build) és az IPA csomagolása sikeres volt; a folyamat a **Verify IPA configuration** lépésben állt meg (`exit code 1`). A Windows-naplóból **nem derül ki a hibás Info.plist kulcs pontos neve**, mert a Verify lépés kimenete nem szerepelt a letöltött Xcode buildlogban.

Az új verzió ezért:

1. a fordítás után, **még az aláíratlan `.app` csomagon**, összeveti a tényleges Info.plist Google OAuth és HealthKit mezőit a forrásértékekkel, és hiány esetén pótolja őket;
2. ellenőrzi a becsomagolt IPA tényleges Info.plist fájlját, és **mezőnként** kiírja a vizsgálat eredményét;
3. feltölti az `ipa-diagnostics` artifactot, amely sikertelenségnél is tartalmazza az `ipa-verification.txt` fájlt;
4. a Windowsos `02_FELHOS_IPA_EPITES.bat` futása az adott GitHub-futás külön mappájába tölti a naplókat, tehát a korábban látott `xcodebuild.log: file exists` hiba nem ismétlődhet emiatt.

## Telepítés a meglévő projektbe

1. Ments el egy másolatot a projektedről.
2. A kis javító ZIP mappaszerkezetét megtartva másold be a `C:\Users\szabo\Desktop\OraNaplo-iOS-Windows` könyvtárba.
3. **Ne módosítsd vagy töröld a `google_oauth.json` fájlt.** A javító ZIP nem írja felül.
4. Indítsd a `01_WINDOWS_ELOKESZITES.bat`, majd a `02_FELHOS_IPA_EPITES.bat` fájlt.
5. A `IGEN` jóváhagyás nyilvános GitHub-feltöltést jelent. Csak akkor engedélyezd, ha valóban szeretnéd feltölteni az ellenőrzött forrásfájlokat.

Ha továbbra is sikertelen a Verify lépés, az `output\diagnostics-<futásszám>\ipa-verification.txt` fájlból már kiolvasható a pontos hiba. A GitHub Actions oldalán a `ipa-diagnostics` artifact szintén letölthető. Ha az `Unsigned build` piros, az `output\build-logs-<futásszám>\xcodebuild.log` fájlt kell vizsgálni.

## Mit NEM bizonyít a sikeres futás?

A sikeres ellenőrzés **csak az aláíratlan IPA-ban lévő Info.plist állapotát bizonyítja**. Nem ellenőrzi, hogy a Sideloadly milyen Bundle ID-val és milyen jogosultságokkal írja alá a telepített alkalmazást. Az ingyenes Apple-fiók korlátozhatja a HealthKit-jogosultságot; ezt kóddal nem lehet megkerülni. Ha a Google OAuth azonosító eltér a Sideloadly által telepített alkalmazás tényleges Bundle ID-jától, a bejelentkezés továbbra sem fog működni.

A helyi Swift szintaktikai és Python tesztek nem helyettesítik a macOS-en végzett valódi fordítást, és a telefonos próba sem helyettesíti az engedélyek ellenőrzését.
