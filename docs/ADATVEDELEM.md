# Adatvédelem és technikai biztonság

- Az app Google Sign-In SDK-val hitelesít; Gmail-jelszót a fejlesztő soha nem kér.
- A kért `drive.file` hatókör hozzáférést korlátozza az app által használt/létrehozott fájlokra.
- A készülék az API-n keresztül a saját Google-táblázatba küldi az adatokat; ÓraNapló-központi egészségadatszerver nincs.
- Ideiglenes sor és azonosítók az iPhone alkalmazás-sandboxában tárolódnak. A helyi queue-ban érzékeny egészségadat is lehet; eszközzár és iOS-titkosítás szükséges. Éles kiadás előtt a fájlvédelem és tárolási ciklus külön ellenőrzendő.
- A 100 méteres részidőket GPS-útvonalból számítja, de **a GPS-koordinátákat nem írja a Google Sheetsbe**.
- Ha HealthKitből törlődik egy minta, a jelenlegi prototípus a törlést `törölve` sorral naplózza, de a korábban exportált Google Sheets-sor automatikus törlése még nincs megoldva.
- A lokális deduplikáció hálózati hiba esetén nem garantál pontosan egyszeri írást; éles verzió előtt szerveroldali tranzakció vagy céloldali ID-ellenőrzés kell.
- EKG és más egészségadatok kezelése különösen érzékeny; az alkalmazás nem orvosi diagnosztikai eszköz.
- Nyilvános GitHub-repóba kizárólag forráskód és nyilvános Google OAuth kliensazonosító kerülhet; SOHA ne tölts fel egészségadatot, jelszót, `.p12` vagy más magánkulcsot.
- Ha előfizetéses, fizetős ügyfeleket szolgál ki, a GDPR, az App Store HealthKit-szabályok, adatmegőrzés és törlési kérelmek külön szabályozást és felülvizsgálatot igényelnek.
