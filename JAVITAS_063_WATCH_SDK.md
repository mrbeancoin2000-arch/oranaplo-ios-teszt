# ÓraNapló 0.6.1 – Apple SDK célplatform-javítás (CI 0.6.3)

A GitHub Actions 43079949658 számú futása eljutott az Apple SDK-fordításig. Az első hiba:
`WatchWorkout.swift: error: HKLiveWorkoutBuilder is unavailable in iOS`.

## Mi történt?

A `tools/ci_xcode_build.sh` a teljes, iOS appot és beágyazott watchOS appot
is tartalmazó séma építésekor `-sdk iphonesimulator` paramétert adott az
Xcode-nak. Ez a Watch-célprogram SDK-ját is tévesen iOS-re kényszerítheti.
A `WCSessionDelegate` iOS-specifikus megfelelőségi hibája ugyanebből eredhet.

## Javítás

A script immár **csak `-destination`-t használ** (`generic/platform=iOS Simulator`,
`generic/platform=iOS`, illetve `generic/platform=watchOS Simulator`).
Az Xcode az egyes targetekhez az adott platform SDK-ját választhatja ki.
A `WatchWorkout.swift` fájlból nem töröltünk Watch-képességeket.
Az új automatikus regressziós teszt (`tests/test_063_multiplatform_sdk.py`)
a tényleges `xcodebuild` argumentumokat is ellenőrzi egy helyi mockkal.

## Mit csinálj?

1. Az előző mappádat tartsd meg biztonsági mentésnek.
2. Csomagold ki ezt a teljes ZIP-et új mappába. A régi, személyes
   `google_oauth.json` konfigurációt másold át az új mappába.
3. Indítsd el a `00_MINDENT_INDIT.bat`-ot, vagy csak a
   `02_FELHOS_IPA_EPITES.bat`-ot.
4. A GitHub Actions-nél ellenőrizd, hogy a `Unsigned iOS simulator build with real Apple SDK`
   lépés zöldre vált-e, majd a `Blocking watchOS simulator build` is.
5. Újabb hiba esetén a friss `output/build-logs-<RUN_ID>/xcodebuild-simulator.log`,
   `xcodebuild-watchsimulator.log` és `xcodebuild.log` fájlokat küldd el.

**Még nem igazoltuk, hogy a valódi Xcode-fordítás sikeres!**
A változást csak a következő macOS-es GitHub Actions futás igazolhatja.
A tagság megvásárlása ehhez továbbra sem szükséges.
