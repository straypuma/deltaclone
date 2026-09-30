import SwiftUI

/// One crypto or cash holding: its balance and the transactions behind it.
struct HoldingDetailView: View {
    let ref: HoldingRef
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency
    @State private var selection = Set<UUID>()

    var body: some View {
        if let info = HoldingInfo(ref: ref, valuation: store.valuation(in: base)) {
            VStack(spacing: 0) {
                header(info)
                Divider()
                table(info)
                if info.holding.transactions.isEmpty { emptyHint }
            }
            .navigationTitle(info.name)
            .navigationSubtitle(info.subtitle)
            .toolbar {
                ToolbarItem {
                    Button { navigator.sheet = info.editSheet } label: {
                        Label("Edit Holding", systemImage: "pencil")
                    }
                    .help("Edit label and starting balance")
                }
                MainToolbar()
            }
            .focusedSceneValue(\.transactionTarget, ref)
            .focusedSceneValue(\.deleteSelection, deletable(info).isEmpty ? nil
                : DeleteSelection(count: deletable(info).count, noun: "Transaction") {
                    store.deleteTransactions(deletable(info), from: ref)
                })
        } else {
            ContentUnavailableView("Holding Removed", systemImage: "tray")
        }
    }

    private func header(_ info: HoldingInfo) -> some View {
        HStack(spacing: 14) {
            AssetIcon(icon: info.icon, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(info.quantity(info.holding.balance))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .privacySensitive()
                    .accessibilityIdentifier("holding-balance")
                HStack(spacing: 6) {
                    Text(Format.money(info.value, base))
                        .privacySensitive()
                        .accessibilityIdentifier("holding-value")
                    if let unitPrice = info.unitPrice, info.unit != base {
                        Text("· 1 \(info.unit) = \(Format.price(unitPrice, base))")
                    }
                }
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            if let change = info.change24h {
                VStack(alignment: .trailing, spacing: 4) {
                    ChangeLabel(percent: change)
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(.snappy, value: info.holding.balance)
    }

    private func table(_ info: HoldingInfo) -> some View {
        Table(info.rows, selection: $selection) {
            TableColumn("Date") { row in
                Text(row.transaction?.date.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    .foregroundStyle(row.transaction == nil ? .secondary : .primary)
                    .tableCell()
            }
            .width(min: 90, ideal: 110)

            TableColumn("Type") { row in
                Text(row.transaction?.kind.title(cash: info.isCash) ?? "Starting balance")
                    .foregroundStyle(row.transaction == nil ? .secondary : .primary)
                    .tableCell()
            }
            .width(min: 90, ideal: 120)

            TableColumn("Amount") { row in
                Text(row.transaction == nil ? info.quantity(row.change) : info.quantity(row.change, signed: true))
                    .foregroundStyle(row.transaction == nil ? .primary : row.change >= 0 ? Color.green : Color.red)
                    .monospacedDigit()
                    .privacySensitive()
                    .tableCell(.trailing)
            }
            .alignment(.trailing)

            if !info.isCash {
                TableColumn("Price") { row in
                    Text(row.transaction.flatMap { t in t.price.map { Format.price($0, t.priceCurrency ?? base) } } ?? "")
                        .monospacedDigit()
                        .tableCell(.trailing)
                }
                .alignment(.trailing)

                TableColumn("Total") { row in
                    Text(row.transaction.flatMap { t in t.total.map { Format.money($0, t.priceCurrency ?? base) } } ?? "")
                        .monospacedDigit()
                        .privacySensitive()
                        .tableCell(.trailing)
                }
                .alignment(.trailing)
            }

            TableColumn("Balance") { row in
                Text(info.quantity(row.balanceAfter))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .privacySensitive()
                    .tableCell(.trailing)
            }
            .alignment(.trailing)

            TableColumn("Note") { row in
                Text(row.transaction?.note ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .tableCell()
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .accessibilityIdentifier("transactions-table")
        .contextMenu(forSelectionType: UUID.self) { ids in
            let picked = info.holding.transactions.filter { ids.contains($0.id) }
            if picked.count == 1 {
                Button("Edit…") { navigator.sheet = .transaction(ref, picked[0]) }
            } else if picked.isEmpty && ids.contains(info.holding.id) {
                Button("Edit Starting Balance…") { navigator.sheet = info.editSheet }
            }
            if !picked.isEmpty {
                Button("Delete", role: .destructive) { store.deleteTransactions(Set(picked.map(\.id)), from: ref) }
            }
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            if let transaction = info.holding.transactions.first(where: { $0.id == id }) {
                navigator.sheet = .transaction(ref, transaction)
            } else {
                navigator.sheet = info.editSheet
            }
        }
    }

    private var emptyHint: some View {
        HStack {
            Text("Log a buy, sell or transfer and the balance updates automatically.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Add Transaction…") { navigator.sheet = .transaction(ref, nil) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Selected transactions only; the starting-balance row can't be deleted.
    private func deletable(_ info: HoldingInfo) -> Set<UUID> {
        selection.intersection(info.holding.transactions.map(\.id))
    }
}

// MARK: - Model for the page

struct HoldingInfo {
    struct Row: Identifiable {
        let id: UUID
        let transaction: AssetTransaction?  // nil for the starting balance
        let change: Double
        let balanceAfter: Double
    }

    let name: String
    let subtitle: String
    let icon: AssetLine.Icon
    let isCash: Bool
    let unit: String                // "ETH" or a currency code
    let holding: any LedgerHolding
    let unitPrice: Double?          // one unit, in the display currency
    let value: Double?
    let change24h: Double?
    let editSheet: ActiveSheet

    init?(ref: HoldingRef, valuation: Valuation) {
        switch ref {
        case .crypto(let id):
            guard let row = valuation.crypto.first(where: { $0.id == id }) else { return nil }
            let h = row.holding
            name = h.name
            unit = h.symbol.uppercased()
            subtitle = h.label.isEmpty ? unit : "\(unit) · \(h.label)"
            icon = .remote(row.imageURL)
            isCash = false
            holding = h
            unitPrice = row.price
            value = row.value
            change24h = row.change24h
            editSheet = .crypto(h)
        case .cash(let id):
            guard let row = valuation.cash.first(where: { $0.id == id }) else { return nil }
            let h = row.holding
            name = Currency.name(h.currency)
            unit = h.currency
            subtitle = h.label.isEmpty ? unit : "\(unit) · \(h.label)"
            icon = .currency(h.currency)
            isCash = true
            holding = h
            unitPrice = row.unitValue
            value = row.value
            change24h = nil
            editSheet = .cash(h)
        }
    }

    /// Newest first, with the starting balance pinned at the bottom.
    var rows: [Row] {
        holding.ledger.reversed().map {
            Row(id: $0.transaction.id, transaction: $0.transaction,
                change: $0.transaction.signedQuantity, balanceAfter: $0.balanceAfter)
        } + [Row(id: holding.id, transaction: nil, change: holding.startingAmount, balanceAfter: holding.startingAmount)]
    }

    func quantity(_ value: Double, signed: Bool = false) -> String {
        if isCash { return signed ? Format.signedMoney(value, unit) : Format.money(value, unit) }
        return (signed ? Format.signedAmount(value) : Format.amount(value)) + " " + unit
    }
}
