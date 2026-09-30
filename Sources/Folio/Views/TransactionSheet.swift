import SwiftUI

/// Add or edit a buy, sell or transfer on a crypto or cash holding.
struct TransactionSheet: View {
    let ref: HoldingRef
    let existing: AssetTransaction?
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.baseCurrency, store: Pref.defaults) private var base = Pref.defaultCurrency

    @State private var kind: AssetTransaction.Kind
    @State private var quantityText: String
    @State private var priceText: String
    @State private var date: Date
    @State private var note: String

    init(ref: HoldingRef, existing: AssetTransaction?) {
        self.ref = ref
        self.existing = existing
        let isCash = if case .cash = ref { true } else { false }
        _kind = State(initialValue: existing?.kind ?? (isCash ? .receive : .buy))
        _quantityText = State(initialValue: existing.map { Format.editableAmount($0.quantity) } ?? "")
        _priceText = State(initialValue: existing?.price.map { Format.editableAmount($0) } ?? "")
        _date = State(initialValue: existing?.date ?? .now)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        if let info = HoldingInfo(ref: ref, valuation: store.valuation(in: priceCurrency)) {
            form(info)
        } else {
            ContentUnavailableView("Holding Removed", systemImage: "tray")
                .frame(width: 440, height: 240)
        }
    }

    private func form(_ info: HoldingInfo) -> some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(AssetTransaction.Kind.options(cash: info.isCash)) { Text($0.title(cash: info.isCash)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("transaction-kind")

                    TextField("Amount (\(info.unit))", text: $quantityText, prompt: Text("0"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quantity")

                    if showsPrice {
                        TextField("\(kind == .receive ? "Cost" : "Price") per \(info.unit) (\(priceCurrency))", text: $priceText, prompt: Text("Optional"))
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("price")
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Note", text: $note, prompt: Text("Optional"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("note")
                } header: {
                    Text("\(info.name) · \(info.subtitle)")
                } footer: {
                    footer(info)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let existing {
                    Button("Delete", role: .destructive) {
                        store.deleteTransactions([existing.id], from: ref)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave(info))
                    .accessibilityIdentifier("confirm")
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 4)
        }
        .frame(width: 460, height: showsPrice ? 372 : 330)
        .animation(.snappy, value: showsPrice)
        .onAppear {
            // Default a new trade to today's price; the user can overwrite it.
            if existing == nil, priceText.isEmpty, !info.isCash, let price = info.unitPrice {
                priceText = Format.editableAmount((price * 100).rounded() / 100)
            }
        }
    }

    @ViewBuilder
    private func footer(_ info: HoldingInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let after = balanceAfter(info) {
                if after < -1e-9 {
                    Text("You only have \(info.quantity(balanceBefore(info))).")
                        .foregroundStyle(.red)
                } else {
                    Text("Balance after: \(info.quantity(after))")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("balance-after")
                }
            }
            if showsPrice, let quantity, let price, price > 0 {
                Text("Total: \(Format.money(quantity * price, priceCurrency))")
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    // MARK: Values

    private var isCash: Bool { if case .cash = ref { true } else { false } }

    /// Crypto buys, sells and receives record a price; it's what profit is calculated from.
    private var showsPrice: Bool { !isCash && kind.hasPrice }

    /// Prices are recorded in the display currency at the time (kept as-is when editing).
    private var priceCurrency: String { existing?.priceCurrency ?? base }

    private var quantity: Double? {
        Format.parseAmount(quantityText).flatMap { $0 > 0 ? $0 : nil }
    }

    /// nil when blank (price is optional) — `priceIsValid` catches unparseable input.
    private var price: Double? { Format.parseAmount(priceText) }
    private var priceIsValid: Bool {
        !showsPrice || priceText.trimmingCharacters(in: .whitespaces).isEmpty || (price ?? -1) >= 0
    }

    private func balanceBefore(_ info: HoldingInfo) -> Double {
        info.holding.balance - (existing?.signedQuantity ?? 0)
    }

    private func balanceAfter(_ info: HoldingInfo) -> Double? {
        quantity.map { balanceBefore(info) + (kind.isInflow ? $0 : -$0) }
    }

    private func canSave(_ info: HoldingInfo) -> Bool {
        guard let after = balanceAfter(info) else { return false }
        return after >= -1e-9 && priceIsValid
    }

    private func save() {
        guard let quantity else { return }
        let recordedPrice = showsPrice ? price : nil
        let transaction = AssetTransaction(
            id: existing?.id ?? UUID(),
            kind: kind,
            date: date,
            quantity: quantity,
            price: recordedPrice,
            priceCurrency: recordedPrice == nil ? nil : priceCurrency,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        store.save(transaction, to: ref)
        dismiss()
    }
}
