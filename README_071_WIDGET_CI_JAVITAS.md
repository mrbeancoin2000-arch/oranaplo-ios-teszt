# ÓraNapló 0.7.0 – GitHub CI widgetforrás feltöltési hiba javítása

Az előző GitHub Actions futásban a `test_widgets_not_added_to_sideload_build` teszt azért bukott, mert a helyi ZIP-ben létező `widgets/iOS/OraNaploWidgets.swift` fájlt a `tools/cloud_build.ps1` biztonságos feltöltési listája nem másolta a GitHubra. A Windows helyi teszt ezért volt zöld, de a macOS teszt piros.

**Javítás:** a `widgets` mappa `.swift` és `.md` fájljait mostantól kizárólag forrásfájlként a GitHubra töltjük. Az ellenőrzőszkript még a feltöltés előtt hibát jelez, ha bármelyik két WidgetKit-forrás hiányzik. A `project.watch.yml` fájlban továbbra sincs WidgetKit extension target: a widgetek NEM kerülnek bele az IPA-ba és a telefonon még NEM használhatók.

## Teendők

1. Az új ZIP-et csomagold ki külön mappába. A korábbi helyi adatokat, naplókat, Google-konfigurációt őrizd meg.
2. A korábban működő `google_oauth.json` fájlt másold az új mappa gyökerébe, de ne töltsd fel a nyilvános GitHubra.
3. Indítsd el a `05_FIZETES_ELOTTI_TESZTEK.bat`, majd a `02_FELHOS_IPA_EPITES.bat` fájlt.
4. A `GitHub Actions` új futásában ellenőrizd a `Prepayment offline tests` és az Apple SDK buildlépések eredményét.
5. Ha piros, küldd el az új `github-failed-steps.log` és `xcodebuild*.log` fájlokat.

Ne töröld a meglévő, működő iPhone-alkalmazást, amíg az új változat adatmegőrzése nincs ellenőrizve. A sikeres helyi teszt nem garantálja a következő Apple SDK-s fordítás sikerét.
