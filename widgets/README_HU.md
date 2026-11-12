# WidgetKit bővítmény – külön aláírást és App Groupot igényel

A `widgets/iOS` a kezdőképernyős és zárolt képernyős WidgetKit-kódot, a `widgets/watchOS` a Watch számlapos / Smart Stack widget kódját tartalmazza. A fő projektben **szándékosan nincs hozzáadva** egyik extension target sem, mert az aláíratlan és ingyenesen Sideloadlyval aláírt meglévő fő IPA telepíthetőségét nem ronthatjuk.

Tényleges bekapcsoláshoz:
1. Apple fejlesztői fiókkal két új WidgetKit Extension target szükséges Xcode-ban; ugyanazzal a provisioning profile-lal kell aláírni a megfelelő alkalmazás-targettel.
2. iOS App Group `group.hu.oranaplo.shared`, Watch App Group `group.hu.oranaplo.watch` beállítása mind a host, mind a widget extension targethez.
3. A fő alkalmazásban a **WidgetCache** opt-in bekapcsolása; a Watch-oldalon WatchWorkout méréseinek megosztott cache-beli frissítése.
4. Az extension `Info.plist` és embedding ellenőrzése; külön watchOS/iOS widget build, telepítés, különböző nyelvek tesztelése.
5. Csak a készüléken jóváhagyott, legutóbbi *gyorsítótárazott* értékek jelenhetnek meg; sem a widget, sem a háttérszinkron nem jelent folyamatos monitorozást.

Nincs igazolva, hogy ingyenes Sideloadly és HealthKit/App Group jogosultsággal működik; ezért ez fejlesztői alap, nem kész felhasználói funkció.
