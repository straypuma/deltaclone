import SwiftUI

struct CryptoView: View {
    let valuation: Valuation
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\CryptoRow.sortValue, order: .reverse)]

    var body: some View {
        if valuation.crypto.isEmpty {
            ContentUnavailableView {
                Label("No Crypto", systemImage: AssetCategory.crypto.systemImage)
            } description: {
                Text("Add the coins you hold and Folio will keep their value up to date.")
            } actions: {
                Button("Add Crypto") { navigator.sheet = .crypto(nil) }
            }
        } else {
            VStack(spacing: 0) {
                SummaryHeader(title: "Crypto", value: valuation.total(.crypto), currency: valuation.base,
                              change: valuation.change(.crypto), changePercent: valuation.changePercent(.crypto))
                Divider()
                table
            }
        }
    }

    private var table: some View {
        Table(valuation.crypto.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Asset", value: \.name) { row in
                HStack(spacing: 10) {
                    RemoteImage(url: row.imageURL, maxPixel: 72)
                        .frame(width: 24, height: 24)
                        .clipShape(.circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).fontWeight(.medium)
                        Text(subtitle(row.holding)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
                .tableCell()
            }
            .width(min: 180, ideal: 240)

            TableColumn("Price", value: \.sortPrice) { row in
                Text(Format.price(row.price, valuation.base)).monospacedDigit()
                    .tableCell(.trailing)
            }
            .alignment(.trailing)

            TableColumn("24h", value: \.sortChange) { row in
                ChangeLabel(percent: row.change24h)
                    .tableCell(.trailing)
            }
            .width(min: 70, ideal: 80)
            .alignment(.trailing)

            TableColumn("7 Days") { row in
                Sparkline(values: row.sparkline).frame(height: 22)
                    .tableCell()
            }
            .width(min: 70, ideal: 90)

            TableColumn("Holdings", value: \.amount) { row in
                Text("\(Format.amount(row.amount)) \(row.holding.symbol.uppercased())")
                    .monospacedDigit().privacySensitive()
                    .tableCell(.trailing)
            }
            .alignment(.trailing)

            TableColumn("Value", value: \.sortValue) { row in
                Text(Format.money(row.value, valuation.base))
                    .monospacedDigit().fontWeight(.medium).privacySensitive()
                    .tableCell(.trailing)
            }
            .alignment(.trailing)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .accessibilityIdentifier("crypto-table")
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let holding = holding(ids.first) {
                Button("Show Transactions") { navigator.path.append(.crypto(holding.id)) }
                Button("Add Transaction…") { navigator.sheet = .transaction(.crypto(holding.id), nil) }
                Divider()
                Button("Edit…") { navigator.sheet = .crypto(holding) }
            }
            if !ids.isEmpty {
                Button("Delete", role: .destructive) { store.deleteCrypto(ids) }
            }
        } primaryAction: { ids in
            if let id = ids.first { navigator.path.append(.crypto(id)) }
        }
        .onDeleteCommand { store.deleteCrypto(selection) }
        .focusedSceneValue(\.deleteSelection, selection.isEmpty ? nil : DeleteSelection(count: selection.count) {
            store.deleteCrypto(selection)
        })
        .focusedSceneValue(\.transactionTarget, selection.count == 1 ? selection.first.map { .crypto($0) } : nil)
    }

    private func holding(_ id: UUID?) -> CryptoHolding? {
        store.portfolio.crypto.first { $0.id == id }
    }

    private func subtitle(_ h: CryptoHolding) -> String {
        h.label.isEmpty ? h.symbol.uppercased() : "\(h.symbol.uppercased()) · \(h.label)"
    }
}

// MARK: - Add / edit

struct CryptoSheet: View {
    let existing: CryptoHolding?
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency

    @State private var coin: Coin?
    @State private var query = ""
    @State private var results: [CoinSearchResult] = []
    @State private var searchState = SearchState.idle
    @State private var amountText: String
    @State private var label: String
    @FocusState private var amountFocused: Bool

    struct Coin { var id, name, symbol: String; var image: URL? }
    enum SearchState: Equatable { case idle, searching, failed(String) }

    init(existing: CryptoHolding?) {
        self.existing = existing
        _coin = State(initialValue: existing.map { Coin(id: $0.coinID, name: $0.name, symbol: $0.symbol, image: $0.imageURL) })
        _amountText = State(initialValue: existing.map { Format.editableAmount($0.startingAmount) } ?? "")
        _label = State(initialValue: existing?.label ?? "")    }

    private var amount: Double? { Format.parseAmount(amountText) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let coin {
                    Section("Coin") {
                        HStack(spacing: 10) {
                            RemoteImage(url: coin.image ?? store.market.coins[coin.id]?.imageURL, maxPixel: 84).frame(width: 28, height: 28).clipShape(.circle)
                            Text(coin.name).fontWeight(.medium)
                            Text(coin.symbol.uppercased()).foregroundStyle(.secondary)
                            Spacer()
                            if existing == nil {
                                Button("Change") { self.coin = nil }
                            }
                        }
                    }
                    Section {
                        TextField(hasTransactions ? "Starting balance" : "Amount", text: $amountText, prompt: Text("0.0"))
                            .focused($amountFocused)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("amount")
                        TextField("Label", text: $label, prompt: Text("Optional, e.g. Ledger or Coinbase"))
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("label")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let existing, hasTransactions, let balance = effectiveBalance {
                                let count = existing.transactions.count
                                Text("With \(count) transaction\(count == 1 ? "" : "s"), the balance is \(Format.amount(balance)) \(existing.symbol.uppercased()).")
                            }
                            if let value = estimatedValue {
                                Text("≈ \(Format.money(value, base))")
                            }
                        }
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                } else {
                    Section {
                        TextField("Search", text: $query, prompt: Text("Search by name or symbol"))
                            .labelsHidden()
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("coin-search")
                    } footer: {
                        switch searchState {
                        case .searching: ProgressView().controlSize(.small)
                        case .failed(let message): Text(message).foregroundStyle(.red)
                        case .idle: EmptyView()
                        }
                    }
                    if !results.isEmpty {
                        Section("Results") {
                            ForEach(results.prefix(8)) { result in
                                Button { choose(result) } label: { resultRow(result) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("coin-result-\(result.id)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(coin == nil || amount == nil)
                    .accessibilityIdentifier("confirm")
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 4)
        }
        .frame(width: 440, height: coin == nil ? 480 : 310)
        .animation(.snappy, value: coin == nil)
        .task(id: query) { await search() }
    }

    private func resultRow(_ r: CoinSearchResult) -> some View {
        HStack(spacing: 10) {
            RemoteImage(url: r.large, maxPixel: 72).frame(width: 24, height: 24).clipShape(.circle)
            Text(r.name)
            Text(r.symbol.uppercased()).foregroundStyle(.secondary)
            Spacer()
            if let rank = r.marketCapRank {
                Text("#\(rank)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
        .contentShape(.rect)
    }

    private var hasTransactions: Bool { !(existing?.transactions.isEmpty ?? true) }

    /// The entered amount is the starting balance; transactions apply on top of it.
    private var effectiveBalance: Double? {
        guard let amount else { return nil }
        guard var holding = existing else { return amount }
        holding.startingAmount = amount
        return holding.balance
    }

    private var estimatedValue: Double? {
        guard let coin, let balance = effectiveBalance, let usd = store.market.coins[coin.id]?.price else { return nil }
        let rate = base == "USD" ? 1 : store.market.usdRates[base]
        return rate.map { balance * usd * $0 }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; searchState = .idle; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searchState = .searching
        do {
            let found = try await MarketAPI(apiKey: Pref.defaults.string(forKey: Pref.apiKey)).search(q)
            guard !Task.isCancelled else { return }
            results = found
            searchState = .idle
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { searchState = .failed(error.localizedDescription) }
        }
    }

    private func choose(_ r: CoinSearchResult) {
        coin = Coin(id: r.id, name: r.name, symbol: r.symbol, image: r.large)
        amountFocused = true
    }

    private func save() {
        guard let coin, let amount else { return }
        var holding = existing ?? CryptoHolding(coinID: coin.id, symbol: coin.symbol, name: coin.name, startingAmount: amount)
        holding.imageURL = holding.imageURL ?? coin.image
        holding.startingAmount = amount
        holding.label = label.trimmingCharacters(in: .whitespaces)
        store.save(holding)
        dismiss()
    }
}
