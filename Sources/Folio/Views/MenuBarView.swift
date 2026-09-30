import SwiftUI

struct MenuBarLabel: View {
    @Environment(PortfolioStore.self) private var store
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency
    @AppStorage(Pref.hideBalances, store: Pref.defaults) private var hideBalances = false
    @AppStorage(Pref.menuBarShowsTotal, store: Pref.defaults) private var showsTotal = true

    var body: some View {
        if showsTotal && !hideBalances {
            Text(Format.wholeMoney(store.valuation(in: base).total, base))
        } else {
            Image(systemName: "chart.pie.fill")
        }
    }
}

struct MenuBarView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency
    @AppStorage(Pref.hideBalances, store: Pref.defaults) private var hideBalances = false

    var body: some View {
        let valuation = store.valuation(in: base)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Net Worth").font(.caption).foregroundStyle(.secondary)
                Text(Format.money(valuation.total, base))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .privacySensitive()
                ChangeLabel(percent: valuation.change24hPercent, amount: valuation.change24h, currency: base)
                    .font(.callout)
            }

            Divider()

            ForEach(AssetCategory.allCases) { category in
                Button { open(SidebarItem(rawValue: category.rawValue)) } label: {
                    HStack {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(category.color)
                            .frame(width: 18)
                        Text(category.title)
                        Spacer()
                        Text(Format.money(valuation.total(category), base))
                            .monospacedDigit()
                            .privacySensitive()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Button("Open Folio") { open(nil) }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh prices")
                .disabled(store.isRefreshing)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Folio")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 280)
        .redacted(reason: hideBalances ? .privacy : [])
    }

    private func open(_ item: SidebarItem?) {
        if let item { navigator.selection = item }
        openWindow(id: "main")
        NSApp.activate()
    }
}
