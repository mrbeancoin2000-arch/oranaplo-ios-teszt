# ÓraNapló 0.4.3 – TELJES PROJEKT (APPLE-ELŐFIZETÉS ÉS JOGI ELŐKÉSZÍTÉS)

Ez a ZIP a korábbi 0.4.2 **összes forrásfájlját** tartalmazza, az új 0.4.3 módosításokkal. A helyi 0.4.3 projekt még **nem kész App Store-kiadás**.

1. Indulás: `01_WINDOWS_ELOKESZITES.bat`, majd `02_FELHOS_IPA_EPITES.bat`. A meglévő unsigned/Sideloadly-folyamat kizárólag tesztelésre való, és nem biztosítja a HealthKit-jogosultságot.
2. Apple-beállítások és magyar nyelvű részletes teendők: `docs/APP_STORE_KIADAS_043_HU.md`.
3. Háromnyelvű weboldal és jogi sablonok: `website/index.html`; minden nyelvhez `/privacy.html`, `/terms.html`, `/support.html`.
4. A nyilvános URL beállítása a Swift-kódban: `ios/Sources/ReleaseLinks.swift`.
5. Kiadás előtti ellenőrzés: `python tools/release_preflight.py --strict` – **szándékosan hibával kilép**, amíg hiányoznak a valós kapcsolati adatok vagy a `release_manifest.json` igazoltan teljesített kiadási teendői.
6. Automatikus helyi tesztek: `python -m unittest discover -s tests -v`.

Újítások: háromnyelvű, appon belüli adatvédelmi/előfizetési nézet; előfizetés megújulási és lemondási tájékoztató; Cloudflare Pages statikus oldalak; kiadás előtti ellenőrző és dokumentáció.

A 99 USD-os Apple Developer Program, a Paid Apps Agreement, a banki és az Apple által kért adatok, az évi 1 000 Ft-os Pro termék, a 15%-os Small Business Programba jelentkezés és a DSA-kezelés **még nem történt meg**.
