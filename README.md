# Market TV — Apple TV client for the private dashboards

Native tvOS app (SwiftUI + Swift Charts) that shows **US Market Health** (`trader-node:8085`)
and the **P | ANALYTICS** hub status (`trader-node:8087`) on the TV. It only performs
read-only HTTP GETs to endpoints that already exist; nothing on trader-node changes.

| Tab | Source | Refresh |
|---|---|---|
| Market Health | `GET /api/latest?mode=live` + `/app.js` (8085) | 15 min |
| Downturn | `snapshot.downturn_panel` + `card_signals.downturn` from the same record | 15 min |
| Today | `GET /api/today?mode=live` (8085) | 1 min |
| Dashboards | `GET /api/status` (8087) | 30 s |
| Settings | addresses, demo mode, keep-awake | — |

## Single source of truth

The five overview cards, the overall reading and the plain-English downturn names are **not
re-implemented in Swift**. At runtime the app downloads the dashboard's own `/app.js`, extracts the
`// BEGIN market-interpretation-v1 … // END` block plus `fmt`, `signed`, `pct` and
`warningLanguage`, and runs them in JavaScriptCore. It reloads that code whenever
`application.commit` from `/api/latest` changes. If the block is ever renamed or removed, the app
shows "Market interpretation unavailable" instead of guessing.

Downturn ranking, pair selection and statistics come straight from `downturn_panel`; the TV applies
only the same display gate as `warningRate()` (prominent-eligible, ≥10 resolved, finite rate and
baseline) and keeps the "historical associations, not forecasts" wording.

## Install on the Apple TV

0. **Icons** (only if `MarketTV/Assets.xcassets` is missing): in Terminal, inside this folder, run
   `swift Tools/MakeIcons.swift MarketTV/Assets.xcassets`. The app builds without it, just with a blank icon.
1. **Tailscale on the Apple TV**: install it from the App Store, log in, connect and leave it
   connected (no exit node needed, so other apps keep using your normal internet). Make sure your
   tailnet access policy lets the Apple TV reach `100.127.41.102` on ports 8085 and 8087.
2. **Pair the Apple TV with Xcode**: put the Mac and the Apple TV on the same network. On the
   Apple TV open *Settings → Remotes and Devices → Remote App and Devices*. On the Mac open Xcode
   → *Window → Devices and Simulators*, select the Apple TV and enter the code it shows.
3. Open `MarketTV.xcodeproj`. In *Signing & Capabilities* pick your Team (a free Personal Team
   with your Apple ID works). If Xcode says the bundle ID is taken, change
   `org.zapparoli.markettv` to anything unique.
4. Choose the Apple TV as the run destination and press **⌘R**.

With a free Apple ID the install expires after 7 days (just press ⌘R again); a paid developer
account lasts a year.

## Defaults

- Market: `http://100.127.41.102:8085` (Market's listener is IPv4-only and accepts this Host header)
- Hub: `http://100.127.41.102:8087`

Both are editable in Settings. *Demo mode* switches Market Health and Today to the dashboard's
own synthetic fixtures (`mode=demo`) and is clearly labelled DEMO — SYNTHETIC.

## Notes

- Plain HTTP is allowed in `Config/Info.plist` (App Transport Security) because the dashboards are
  HTTP-only inside the tailnet. This is a personal side-loaded app, not for the App Store.
- Requires tvOS 17 or later. Built with Xcode 27.
- The "keep screen awake" setting stops the Apple TV screensaver while the app is in front.
