# ÓraNapló – terjesztés és StoreKit előfizetés (későbbi 99 USD-os fázis)

**Most még NE fizess.** Amikor a termék és a Google Sheets-alapfunkció elkészült, csatlakozz az Apple Developer Programhoz, majd:

1. Hozz létre egy új, **ingyenesen letölthető** iOS-alkalmazást az App Store Connectben, a végleges, stabil bundle ID-val. A Sideloadly-hoz készült ideiglenes azonosítót NE használd nyilvános appazonosítóként.
2. A Signing & Capabilities részen engedélyezd a **HealthKit** funkciót. A tényleges provisioning profile-nak tartalmaznia kell a `com.apple.developer.healthkit` entitlementet. Ellenőrizd az app aláírását, ne csak az Info.plist fájlt.
3. App Store Connect → Subscriptions → hozz létre egy előfizetési csoportot `ÓraNapló Pro` néven, és benne egy **egyéves automatikusan megújuló előfizetést** az alábbi pontos termékazonosítóval:

   `hu.oranaplo.pro.yearly`

4. Magyarországon válassz 1 000 Ft/év árszintet, **ha a rendelkezésre álló Apple-árpontok között választható**. A pontos helyi ár az App Store által megjelenített ár; nem fixáljuk az alkalmazás Swift-kódjában. A többi országban Apple regionális árakat határoz meg vagy te adhatsz meg.
5. Add meg a Pro-termék címét, leírását és az előfizetési csoport nevét **magyarul, angolul és németül**, valamint a szükséges jogi adatokat és képeket.
6. Az alkalmazásban lévő `SubscriptionManager.swift` a StoreKit 2 ellenőrzött tranzakcióit olvassa; nem szabad UserDefaults-szal vagy egyszerű helyi kapcsolóval "aktiválni" a Pro-t.
7. Végezzenek tesztelőid egyedi StoreKit Sandbox-próbát: vásárlás, pending állapot, megszakítás, lejárat, visszatérítés, visszaállítás, fiókváltás, háttérszinkron, offline állapot.
8. A HealthKit és Google OAuth jogosultságokkal kapcsolatos adatvédelmi nyilatkozatot, adatkezelési tájékoztatót, ügyfélszolgálati elérhetőséget és alkalmazáson belüli előfizetéskezelést készítsd el. Google OAuth éles verifikációra a kért Google-scopok alapján szükség lehet.
9. A forrás jelenleg GitHub Actionsban **aláíratlan IPA-t** készít. Az éles terjesztéshez megfelelő Apple-tanúsítvánnyal, provisioning profillal, biztonságos GitHub Secrets-kezeléssel és App Store Connect feltöltéssel bővítendő. Ne tölts fel privát kulcsot vagy tanúsítványt nyilvános repóba!

## Fontos üzleti részletek

- Az **1 000 Ft/év** egy célár, nem jelenlegi működő fizetési kapu. A felhasználó csak a ténylegesen ellenőrzött, érvényes StoreKit-jogosultsággal válik Pro-felhasználóvá.
- Az app ingyenes letöltését az App Store Connectben kell beállítani; az app tartalmazza az ingyenes pulzus funkciót.
- Az előfizetés automatikusan újul; ezt az app három nyelven jelzi és előfizetéskezelő hivatkozást tartalmaz.
- Az Apple ellenőrzésénél alkalmazandó aktuális App Store szabályokat külön is át kell nézni.

Apple dokumentáció: https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/
