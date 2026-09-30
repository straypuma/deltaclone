import SwiftUI

struct CashView: View {
    let valuation: Valuation
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\CashRow.sortValue, order: .reverse)]

    var body: some View {
        if valuation.cash.isEmpty {
            ContentUnavailableView {
                Label("No Cash", systemImage: AssetCategory.cash.systemImage)
            } description: {
                Text("Add balances in any currency. They're converted to \(valuation.base) automatically.")
            } actions: {
                Button("Add Cash") { navigator.sheet = .cash(nil) }
            }
        } else {
            VStack(spacing: 0) {
                SummaryHeader(title: "Cash", value: valuation.total(.cash), currency: valuation.base,
                              detail: currencySummary)
                Divider()
                table
            }
        }
    }

    private var currencySummary: String {
        let count = Set(valuation.cash.map(\.code)).count
        return count == 1 ? "1 currency" : "\(count) currencies"
    }

    private var table: some View {
        Table(valuation.cash.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Currency", value: \.code) { row in
                HStack(spacing: 10) {
                    CurrencyBadge(code: row.code, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Currency.name(row.code)).fontWeight(.medium)
                        Text(row.label.isEmpty ? row.code : "\(row.code) · \(row.label)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
                .tableCell()
            }
            .width(min: 200, ideal: 260)

            TableColumn("Balance", value: \.amount) { row in
                Text(Format.money(row.amount, row.code)).monospacedDigit().privacySensitive()
                    .tableCell(.trailing)
            }
            .alignment(.trailing)

            TableColumn("Rate") { row in
                Text(row.code == valuation.base ? "—" : Format.price(row.unitValue, valuation.base))
                    .monospacedDigit().foregroundStyle(.secondary)
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
        .accessibilityIdentifier("cash-table")
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let holding = holding(ids.first) {
                Button("Show Transactions") { navigator.path.append(.cash(holding.id)) }
                Button("Add Transaction…") { navigator.sheet = .transaction(.cash(holding.id), nil) }
                Divider()
                Button("Edit…") { navigator.sheet = .cash(holding) }
            }
            if !ids.isEmpty {
                Button("Delete", role: .destructive) { store.deleteCash(ids) }
            }
        } primaryAction: { ids in
            if let id = ids.first { navigator.path.append(.cash(id)) }
        }
        .onDeleteCommand { store.deleteCash(selection) }
        .focusedSceneValue(\.deleteSelection, selection.isEmpty ? nil : DeleteSelection(count: selection.count) {
            store.deleteCash(selection)
        })
        .focusedSceneValue(\.transactionTarget, selection.count == 1 ? selection.first.map { .cash($0) } : nil)
    }

    private func holding(_ id: UUID?) -> CashHolding? {
        store.portfolio.cash.first { $0.id == id }
    }
}

// MARK: - Add / edit

struct CashSheet: View {
    let existing: CashHolding?
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency

    @State private var currency: String
    @State private var amountText: String
    @State private var label: String

    init(existing: CashHolding?) {
        self.existing = existing
        _currency = State(initialValue: existing?.currency ?? Pref.defaults.string(forKey: Pref.baseCurrency) ?? Pref.defaultCurrency)
        _amountText = State(initialValue: existing.map { Format.editableAmount($0.startingAmount) } ?? "")
        _label = State(initialValue: existing?.label ?? "")
    }

    private var amount: Double? { Format.parseAmount(amountText) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    CurrencyPicker(title: "Currency", selection: $currency, rates: store.market.usdRates)
                        .accessibilityIdentifier("currency")
                    TextField(hasTransactions ? "Starting balance" : "Amount", text: $amountText, prompt: Text("0.00"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("amount")
                    TextField("Label", text: $label, prompt: Text("Optional, e.g. Checking or Revolut"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("label")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let existing, hasTransactions, let balance = effectiveBalance {
                            let count = existing.transactions.count
                            Text("With \(count) transaction\(count == 1 ? "" : "s"), the balance is \(Format.money(balance, currency)).")
                        }
                        if let balance = effectiveBalance, currency != base, let value = converted(balance) {
                            Text("≈ \(Format.money(value, base))")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil)
                    .accessibilityIdentifier("confirm")
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 4)
        }
        .frame(width: 420, height: 232)
    }

    private var hasTransactions: Bool { !(existing?.transactions.isEmpty ?? true) }

    /// The entered amount is the starting balance; transactions apply on top of it.
    private var effectiveBalance: Double? {
        guard let amount else { return nil }
        guard var holding = existing else { return amount }
        holding.startingAmount = amount
        return holding.balance
    }

    private func converted(_ amount: Double) -> Double? {
        let rates = store.market.usdRates
        guard let from = rates[currency], from > 0, let to = base == "USD" ? 1 : rates[base] else { return nil }
        return amount / from * to
    }

    private func save() {
        guard let amount else { return }
        var holding = existing ?? CashHolding(currency: currency, startingAmount: amount)
        holding.currency = currency
        holding.startingAmount = amount
        holding.label = label.trimmingCharacters(in: .whitespaces)
        store.save(holding)
        dismiss()
    }
}

struct CurrencyPicker: View {
    let title: String
    @Binding var selection: String
    let rates: [String: Double]

    var body: some View {
        let all = Currency.available(rates: rates)
        Picker(title, selection: $selection) {
            Section("Common") {
                ForEach(Currency.common.filter(all.contains), id: \.self, content: row)
            }
            Section("Other Currencies") {
                ForEach(all.filter { !Currency.common.contains($0) }, id: \.self, content: row)
            }
        }
    }

    private func row(_ code: String) -> some View {
        Text("\(Currency.flag(code).map { "\($0)  " } ?? "")\(Currency.name(code)) (\(code))").tag(code)
    }
}
