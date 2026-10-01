import Foundation

enum AssetCategory: String, CaseIterable, Identifiable {
    case crypto, cash, nfts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .crypto: "Crypto"
        case .cash: "Cash"
        case .nfts: "NFTs"
        }
    }

    var systemImage: String {
        switch self {
        case .crypto: "bitcoinsign.circle"
        case .cash: "banknote"
        case .nfts: "photo.on.rectangle.angled"
        }
    }
}

struct CryptoRow: Identifiable {
    let holding: CryptoHolding
    let price: Double?
    let change24h: Double?
    let value: Double?
    let sparkline: [Double]
    let imageURL: URL?
    let performance: Performance?

    var id: UUID { holding.id }
    var name: String { holding.name }
    var amount: Double { holding.balance }
    var sortPrice: Double { price ?? -1 }
    var sortChange: Double { change24h ?? -.infinity }
    var sortValue: Double { value ?? -1 }
    var sortProfit: Double { performance?.total ?? -.infinity }
}

struct CashRow: Identifiable {
    let holding: CashHolding
    let unitValue: Double?      // 1 unit of the currency, in base
    let value: Double?

    var id: UUID { holding.id }
    var code: String { holding.currency }
    var label: String { holding.label }
    var amount: Double { holding.balance }
    var sortValue: Double { value ?? -1 }
}

struct NFTGroup: Identifiable {
    let collection: NFTCollection
    let tokens: [NFTHolding]
    let floorETH: Double?
    let floor: Double?          // in base
    let change24h: Double?
    let imageURL: URL?

    var id: String { collection.rawValue }
    var value: Double? { floor.map { $0 * Double(tokens.count) } }
}

struct HistoryPoint: Identifiable {
    let date: Date
    let value: Double
    var btcPrice: Double? = nil     // one BTC at that moment, in the display currency
    var id: Date { date }
}

/// A single aggregated line for the overview (one per coin, currency, or collection).
struct AssetLine: Identifiable {
    enum Icon { case remote(URL?), currency(String) }
    let id: String
    let category: AssetCategory
    let title: String
    let subtitle: String
    let icon: Icon
    let value: Double
    let change24h: Double?
}

/// Everything the UI shows, converted into the chosen base currency.
struct Valuation {
    let base: String
    let crypto: [CryptoRow]
    let cash: [CashRow]
    let nftGroups: [NFTGroup]
    let total: Double
    let change24h: Double
    let change24hPercent: Double?
    let portfolio: Portfolio
    let market: MarketData
    let usdToBase: Double?
    let assets: [AssetLine]
    /// All-time profit across crypto holdings whose cost is known (or estimated).
    let cryptoProfit: (total: Double, percent: Double?, includesEstimates: Bool)?
    /// Crypto holdings left out of `cryptoProfit` because a price is missing.
    let holdingsWithoutCost: Int
    /// One BTC in the display currency, for showing net worth in bitcoin.
    let btcPrice: Double?
    private let usdRates: [String: Double]

    /// An amount in the display currency, converted to `currency` at today's rate.
    func converted(_ amount: Double, to currency: String) -> Double? {
        if currency == base { return amount }
        guard let from = base == "USD" ? 1 : usdRates[base], from > 0,
              let to = currency == "USD" ? 1 : usdRates[currency] else { return nil }
        return amount / from * to
    }
    private let totals: [AssetCategory: Double]
    private let changes: [AssetCategory: Double]

    func total(_ category: AssetCategory) -> Double { totals[category] ?? 0 }
    func change(_ category: AssetCategory) -> Double { changes[category] ?? 0 }
    func changePercent(_ category: AssetCategory) -> Double? {
        let start = total(category) - change(category)
        return start > 0 ? change(category) / start * 100 : nil
    }

    var isEmpty: Bool { crypto.isEmpty && cash.isEmpty && nftGroups.isEmpty }

    init(portfolio p: Portfolio, market m: MarketData, base: String) {
        self.base = base
        let usdToBase: Double? = base == "USD" ? 1 : m.usdRates[base]
        func toBase(_ usd: Double?) -> Double? {
            guard let usd, let usdToBase else { return nil }
            return usd * usdToBase
        }

        // Recorded prices are in whatever the display currency was at the time.
        func convert(_ amount: Double, from currency: String?) -> Double? {
            guard let currency, currency != base else { return amount }
            guard let rate = m.usdRates[currency], rate > 0 else { return nil }
            return toBase(amount / rate)
        }

        crypto = p.crypto.map { h in
            let quote = m.coins[h.coinID]
            let price = toBase(quote?.price)
            let value = price.map { $0 * h.balance }
            return CryptoRow(holding: h, price: price, change24h: quote?.change24h, value: value,
                             sparkline: quote?.sparkline ?? [], imageURL: quote?.imageURL ?? h.imageURL,
                             performance: Performance(holding: h, currentValue: value, convert: convert))
        }
        let known = crypto.compactMap(\.performance)
        let invested = known.reduce(0) { $0 + $1.invested }
        let profit = known.reduce(0) { $0 + $1.total }
        cryptoProfit = known.isEmpty ? nil
            : (profit, invested > 0 ? profit / invested * 100 : nil, known.contains(where: \.isEstimated))
        holdingsWithoutCost = crypto.count - known.count

        cash = p.cash.map { h in
            let unit: Double?
            if h.currency == base { unit = 1 }
            else if let rate = m.usdRates[h.currency], rate > 0 { unit = toBase(1 / rate) }
            else { unit = nil }
            return CashRow(holding: h, unitValue: unit, value: unit.map { $0 * h.balance })
        }

        nftGroups = NFTCollection.allCases.compactMap { c in
            let tokens = p.nfts.filter { $0.collection == c }.sorted { $0.tokenID < $1.tokenID }
            guard !tokens.isEmpty else { return nil }
            let quote = m.nfts[c.rawValue]
            return NFTGroup(collection: c, tokens: tokens, floorETH: quote?.floorETH,
                            floor: toBase(quote?.floorUSD), change24h: quote?.change24h, imageURL: quote?.imageURL)
        }

        // Change over 24h derived from each asset's percentage move (cash treated as flat).
        func delta(_ value: Double?, _ pct: Double?) -> Double {
            guard let value, let pct, pct > -100 else { return 0 }
            return value - value / (1 + pct / 100)
        }
        let totals: [AssetCategory: Double] = [
            .crypto: crypto.compactMap(\.value).reduce(0, +),
            .cash: cash.compactMap(\.value).reduce(0, +),
            .nfts: nftGroups.compactMap(\.value).reduce(0, +),
        ]
        let changes: [AssetCategory: Double] = [
            .crypto: crypto.reduce(0) { $0 + delta($1.value, $1.change24h) },
            .nfts: nftGroups.reduce(0) { $0 + delta($1.value, $1.change24h) },
        ]
        self.totals = totals
        self.changes = changes
        total = totals.values.reduce(0, +)
        change24h = changes.values.reduce(0, +)
        let start = total - change24h
        change24hPercent = start > 0 ? change24h / start * 100 : nil

        usdRates = m.usdRates
        btcPrice = toBase(m.coins["bitcoin"]?.price)
        portfolio = p
        market = m
        self.usdToBase = usdToBase
        assets = Self.assetLines(crypto: crypto, cash: cash, nfts: nftGroups)
    }

    private static func assetLines(crypto: [CryptoRow], cash: [CashRow], nfts: [NFTGroup]) -> [AssetLine] {
        var lines: [AssetLine] = []
        for (coinID, rows) in Dictionary(grouping: crypto, by: \.holding.coinID) {
            let first = rows[0]
            let amount = rows.reduce(0) { $0 + $1.amount }
            lines.append(AssetLine(id: "crypto-\(coinID)", category: .crypto, title: first.name,
                                   subtitle: "\(Format.amount(amount)) \(first.holding.symbol.uppercased())",
                                   icon: .remote(first.imageURL), value: rows.compactMap(\.value).reduce(0, +),
                                   change24h: first.change24h))
        }
        for (code, rows) in Dictionary(grouping: cash, by: \.code) {
            let amount = rows.reduce(0) { $0 + $1.amount }
            lines.append(AssetLine(id: "cash-\(code)", category: .cash, title: Currency.name(code),
                                   subtitle: Format.money(amount, code), icon: .currency(code),
                                   value: rows.compactMap(\.value).reduce(0, +), change24h: nil))
        }
        for group in nfts {
            let floor = group.floorETH.map { " · floor \(Format.eth($0))" } ?? ""
            lines.append(AssetLine(id: "nft-\(group.id)", category: .nfts, title: group.collection.name,
                                   subtitle: "\(group.tokens.count) owned\(floor)", icon: .remote(group.imageURL),
                                   value: group.value ?? 0, change24h: group.change24h))
        }
        return lines.sorted { $0.value > $1.value }
    }
}
