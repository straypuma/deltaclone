# Folio

A small, native macOS portfolio tracker for crypto, cash and NFTs (Milady Maker, Remilio Babies).
SwiftUI + Swift Charts + WidgetKit, Apple Silicon, ~3 MB.

## Build

```sh
./build.sh            # → build/Folio.app
./build.sh --install  # also copies it to /Applications
./build.sh --test     # runs the UI tests
```

Or open `Folio.xcodeproj` in Xcode. The project uses folder-synced groups, so new files
dropped into `Sources/…` or `Tests/…` are picked up automatically.

| Folder | What's in it |
|---|---|
| `Sources/Folio` | The app |
| `Sources/FolioWidget` | Net Worth widget (small + medium) |
| `Sources/Shared` | Code compiled into both (widget snapshot, sparkline) |
| `Tests/FolioUITests` | UI tests: add / edit / delete for every asset type, transactions, conversion, persistence |
| `Support` | Widget Info.plist + entitlements, icon layer generator |

## Transactions

Double-click any crypto or cash holding to open it. You'll see its balance and a transaction list:
buys, sells, receives and sends for crypto; deposits and withdrawals for cash. The balance is the
starting balance plus every transaction, with a running balance per row. Selling more than you hold
is blocked, and deleting a transaction undoes it. Buys and sells can record a price (pre-filled
with today's).

## Data

- Holdings are plain JSON in **iCloud Drive ▸ Folio ▸ portfolio.json**, so they sync and are backed up
  (File ▸ Show Data File in Finder). Folio reads and writes it with file coordination and reloads when
  another Mac changes it. Settings ▸ “Keep portfolio in iCloud Drive” switches to this Mac only
  (`~/Library/Application Support/Folio`). Whenever a copy is replaced, the old one is kept as a
  dated backup next to it.
- The price cache and the widget's snapshot always stay on this Mac.
- Crypto prices, 7‑day sparklines and NFT floors come from [CoinGecko](https://www.coingecko.com);
  exchange rates from [ExchangeRate-API](https://www.exchangerate-api.com). No keys needed —
  add a free CoinGecko Demo key in Settings if you hit rate limits.
- NFTs are valued at the collection floor. Token images load from miladymaker.net / remilio.org
  and are cached as small thumbnails in `~/Library/Caches/Folio`.
- The widget never goes online: Folio writes `widget.json` next to your portfolio and the
  sandboxed widget only has read access to that folder.
- UI tests run the Debug build against a throwaway folder in `/tmp` with fixed prices
  (`Sources/Folio/Testing`), so they never touch your data or the network.
  None of that code is compiled into Release builds.

## Widget

Right‑click the desktop ▸ Edit Widgets ▸ search “Folio”. It updates whenever Folio refreshes
prices, and hides amounts while Hide Balances is on.

## Icon

`Sources/Folio/Resources/AppIcon.icon` is an Icon Composer file (open it in Icon Composer to tweak
the glass). Its three layers are drawn by `swift Support/make-icon-layers.swift`.

## Shortcuts

| | |
|---|---|
| ⌘N / ⇧⌘N / ⌥⌘N | Add crypto / cash / NFT |
| ⌘T | Add a transaction to the open or selected holding |
| ⌘1 – ⌘4 | Overview, Crypto, Cash, NFTs |
| ⌘R | Refresh prices |
| ⇧⌘H | Hide balances |
| ⌘⌫ | Delete selected holdings or transactions |
| Double‑click | Open a holding (or edit a transaction) |
