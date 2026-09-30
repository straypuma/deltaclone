import SwiftUI

struct ContentView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency
    @AppStorage(Pref.hideBalances, store: Pref.defaults) private var hideBalances = false

    var body: some View {
        if let problem = store.storageProblem {
            ContentUnavailableView {
                Label("Can't Open Your Portfolio", systemImage: "exclamationmark.icloud")
            } description: {
                Text(problem)
            } actions: {
                Button("Try Again") { store.retryOpeningPortfolio() }
                    .buttonStyle(.borderedProminent)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                }
            }
        } else {
            portfolioView
        }
    }

    @ViewBuilder
    private var portfolioView: some View {
        @Bindable var navigator = navigator
        let valuation = store.valuation(in: base)

        NavigationSplitView {
            List(selection: $navigator.selection) {
                sidebarRow(.overview, value: valuation.total)
                Section("Assets") {
                    ForEach([SidebarItem.crypto, .cash, .nfts]) { item in
                        sidebarRow(item, value: valuation.total(item.category!))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            NavigationStack(path: $navigator.path) {
                detail(valuation)
                    .navigationTitle(navigator.selection?.title ?? "Folio")
                    .navigationSubtitle(status)
                    .navigationDestination(for: HoldingRef.self) { HoldingDetailView(ref: $0) }
                    .toolbar { MainToolbar() }
            }
        }
        .sheet(item: $navigator.sheet) { sheet in
            Group {
                switch sheet {
                case .crypto(let holding): CryptoSheet(existing: holding)
                case .cash(let holding): CashSheet(existing: holding)
                case .nft(let collection): NFTSheet(collection: collection ?? .miladyMaker)
                case .transaction(let ref, let transaction): TransactionSheet(ref: ref, existing: transaction)
                }
            }
            .environment(store)
        }
        .redacted(reason: hideBalances ? .privacy : [])
        .onChange(of: base) { store.publishWidgetSnapshot() }
        .onChange(of: hideBalances) { store.publishWidgetSnapshot() }
        .alert("Couldn't Read Portfolio", isPresented: .constant(store.dataWarning != nil)) {
            Button("Show in Finder") { store.revealDataFile(); store.dataWarning = nil }
            Button("OK", role: .cancel) { store.dataWarning = nil }
        } message: {
            Text(store.dataWarning ?? "")
        }
    }

    private func sidebarRow(_ item: SidebarItem, value: Double) -> some View {
        HStack {
            Label(item.title, systemImage: item.systemImage)
            Spacer()
            Text(Format.compactMoney(value, base))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .privacySensitive()
        }
        .tag(item)
    }

    @ViewBuilder
    private func detail(_ valuation: Valuation) -> some View {
        switch navigator.selection ?? .overview {
        case .overview: OverviewView(valuation: valuation)
        case .crypto: CryptoView(valuation: valuation)
        case .cash: CashView(valuation: valuation)
        case .nfts: NFTView(valuation: valuation)
        }
    }

    private var status: String {
        let time = store.market.updated.map { $0.formatted(date: .omitted, time: .shortened) }
        if store.isRefreshing { return "Updating…" }
        if store.lastError != nil { return time.map { "Couldn't refresh · prices from \($0)" } ?? "Couldn't refresh" }
        return time.map { "Updated \($0)" } ?? ""
    }
}

/// Refresh, Hide Balances and Add. Shared by the section pages and holding detail pages,
/// since a pushed page replaces the toolbar on macOS.
struct MainToolbar: ToolbarContent {
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @AppStorage(Pref.hideBalances, store: Pref.defaults) private var hideBalances = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let error = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }

            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .help("Refresh prices (⌘R)")
            .disabled(store.isRefreshing)

            Toggle(isOn: $hideBalances) {
                Label("Hide Balances", systemImage: hideBalances ? "eye.slash" : "eye")
            }
            .help("Hide balances (⇧⌘H)")

            addButton
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if let holding = navigator.path.last {
            Button { navigator.sheet = .transaction(holding, nil) } label: {
                Label("Add Transaction", systemImage: "plus")
            }
            .help("Add a buy, sell or transfer (⌘T)")
        } else {
            sectionAddButton
        }
    }

    @ViewBuilder
    private var sectionAddButton: some View {
        switch navigator.selection ?? .overview {
        case .crypto:
            Button { navigator.sheet = .crypto(nil) } label: { Label("Add Crypto", systemImage: "plus") }
        case .cash:
            Button { navigator.sheet = .cash(nil) } label: { Label("Add Cash", systemImage: "plus") }
        case .nfts:
            Button { navigator.sheet = .nft(nil) } label: { Label("Add NFT", systemImage: "plus") }
        case .overview:
            Menu {
                Button("Crypto…", systemImage: AssetCategory.crypto.systemImage) { navigator.sheet = .crypto(nil) }
                Button("Cash…", systemImage: AssetCategory.cash.systemImage) { navigator.sheet = .cash(nil) }
                Button("NFT…", systemImage: AssetCategory.nfts.systemImage) { navigator.sheet = .nft(nil) }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}
