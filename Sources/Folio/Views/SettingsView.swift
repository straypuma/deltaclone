import SwiftUI

struct SettingsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppUpdater.self) private var updater
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency
    @AppStorage(Pref.refreshMinutes, store: Pref.defaults) private var refreshMinutes = 5
    @AppStorage(Pref.showMenuBarExtra, store: Pref.defaults) private var showMenuBarExtra = false
    @AppStorage(Pref.menuBarShowsTotal, store: Pref.defaults) private var menuBarShowsTotal = true
    @AppStorage(Pref.apiKey, store: Pref.defaults) private var apiKey = ""

    private var storageNote: String {
        if store.isInICloud {
            return "Plain JSON in iCloud Drive ▸ Folio, so it syncs and is backed up. Prices and the widget's data stay on this Mac."
        }
        if PortfolioStore.iCloudDirectory == nil {
            return "Stored as plain JSON on this Mac. Turn on iCloud Drive in System Settings to sync it."
        }
        return "Stored as plain JSON on this Mac only."
    }

    var body: some View {
        @Bindable var updater = updater
        Form {
            Section {
                CurrencyPicker(title: "Display currency", selection: $base, rates: store.market.usdRates)
                Picker("Refresh prices", selection: $refreshMinutes) {
                    Text("Every minute").tag(1)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                }
            }

            Section {
                Toggle("Show in menu bar", isOn: $showMenuBarExtra)
                Toggle("Show net worth in menu bar", isOn: $menuBarShowsTotal)
                    .disabled(!showMenuBarExtra)
            } footer: {
                Text("Folio keeps running in the menu bar after you close its window.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("CoinGecko API key", text: $apiKey, prompt: Text("Optional"))
            } footer: {
                Text("Works without a key. A free [CoinGecko Demo key](https://www.coingecko.com/en/api/pricing) raises rate limits.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep portfolio in iCloud Drive", isOn: Binding(
                    get: { store.isInICloud },
                    set: { store.setICloudStorage($0) }
                ))
                .disabled(PortfolioStore.iCloudDirectory == nil || store.storageProblem != nil)
                LabeledContent("Portfolio file") {
                    Button("Show in Finder") { store.revealDataFile() }
                }
            } footer: {
                Text(storageNote).foregroundStyle(.secondary)
            }

            Section {
                if updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                }
                LabeledContent("Version") {
                    HStack {
                        Text(updater.version).foregroundStyle(.secondary).monospacedDigit()
                        if updater.isAvailable {
                            Button("Check Now") { updater.checkForUpdates() }
                                .disabled(!updater.canCheckForUpdates)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
