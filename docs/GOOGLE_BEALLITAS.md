# Google-fiók – egyszeri OAuth-beállítás

A Sideloadly és a GitHub nem kérheti a Gmail-jelszavadat. A Google-bejelentkezést a **GoogleSignIn-iOS** SDK kezeli, az alkalmazás pedig a `drive.file` hatókört kéri. Ez csak az app által létrehozott/engedélyezett Google fájlokra jogosít.

1. Nyisd meg: https://console.cloud.google.com/ . Hozz létre egy projektet, például `OraNaplo-Test`.
2. **APIs & Services → Library**: engedélyezd a **Google Sheets API**-t. A Drive API későbbi fájlválasztáshoz hasznos lehet; ebben a prototípusban az app új Sheetset készít a Sheets API-val.
3. **Google Auth Platform / OAuth consent screen**: add meg az app nevét, tesztelési e-mail-címet, az adatkezelési információkat. Külső tesztelésnél add hozzá a saját Google-fiókodat a **Test users** listához.
4. **Credentials → Create credentials → OAuth client ID**: platform = **iOS**; a Bundle ID pontosan: `hu.oranaplo.ios`.
5. Másold ki a létrejött **iOS Client ID-t**, majd a `google_oauth.example.json` fájlt másold `google_oauth.json` névre. Írd be a valódi értéket, például:

```json
{"ios_client_id":"1234567890-abcdef.apps.googleusercontent.com"}
```

6. Futtasd a `01_WINDOWS_ELOKESZITES.bat`-ot újra vagy a `python tools/configure.py` parancsot. Az automatikus generátor elkészíti az iOS kliensazonosítót tartalmazó Swift-konstanst és a helyes iOS URL-visszairányítást az Info.plistben.
7. Ezután indítsd a GitHub macOS fordítást.

**Ne használj Web OAuth Client ID-t** ehhez a kódhoz, és ne adj meg client secretet. A *Client ID nyilvános*, de az access token vagy saját Google-hitelesítési cookie **titkos**. A prototípus nem tárol OAuth secretet GitHubon.

A nyilvános, fizetős termékhez a Google OAuth consent screen teszt üzemmódját rendezni és adott esetben alkalmazásellenőrzést kérni kell. A `drive.file` korlátozottabb hatókör, de az alkalmazás ellenőrzése ettől még szükséges lehet.

Hivatalos leírások:
- https://developers.google.com/identity/sign-in/ios/start-integrating
- https://developers.google.com/workspace/sheets/api/scopes
- https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/create


## 2026-11-10 – Beállítási figyelmeztetés
Ez a teljes projekt már tartalmazhatja a korábban megadott **nyilvános** `google_oauth.json` beállításokat. Ne töröld, amikor új ZIP-et bontasz ki. Ha a Google Cloudban másik OAuth klienst hoztál létre, ugyanitt frissítsd az ID-t és a telepített Sideloadly Bundle ID-t. A `configure.py` demó-beállítással nem enged buildet.
