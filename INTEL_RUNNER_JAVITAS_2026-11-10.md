# ÓraNapló – macOS runner hibajavítás

## A jelenlegi hiba oka
A GitHub Actions nem tudott macOS ARM64 futtatót lefoglalni: `The job was not acquired by Runner of type hosted even after multiple attempts` és `Internal server error`. Emiatt **nem történt Xcode-fordítás**, az alkalmazás Swift-kódjáról még nem mondható el, hogy lefordul-e.

## Mi változott?
- A `.github/workflows/macos-ipa.yml` alapértelmezett runnerje `macos-15-intel`, mert az előző `macos-15` macOS ARM64-et használ, és annál kapacitáshiány jelentkezett.
- A workflow kézzel másik futtatón is elindítható (pl. `macos-26-intel`, vagy újra ARM64).
- A `tools/cloud_build.ps1` az Intel opcióval indít; hiba esetén nem állítja tévesen automatikusan, hogy az Xcode fordítása hibázott, és megadja a GitHub naplóhoz vezető linket.

## Használat
1. Csomagold ki a **kis hibajavító ZIP** tartalmát a meglévő `OraNaplo-iOS-Windows` mappába, a fájlok felülírásával.
2. Futtasd: `02_FELHOS_IPA_EPITES.bat`.
3. Amikor kérdezi a nyilvános repo frissítését, írd be: `IGEN`.
4. Ha megjelenik `Success`, az `output` mappába kerülhet az aláíratlan IPA.
5. `Failure` esetén nyisd meg a GitHub Actionsben az új futást. Ha a build job kapott gépet, akkor a `Runner details`, `Dependencies`, `Unsigned build` lépések naplóit nézd meg.

## Fontos korlát
Az Intel runner sem garancia: a GitHub infrastruktúrája ott is lehet átmenetileg túlterhelt. Ha bármelyik lépésen tényleges Swift/Xcode hiba jelentkezik, annak javításához az új GitHub Actions build log szükséges. Az aláíratlan IPA Sideloadly-n keresztüli sikeres telepítése és a HealthKit-jogosultság továbbra sincs bizonyítva.
