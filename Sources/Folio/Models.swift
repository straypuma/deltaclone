import Foundation

// MARK: - Holdings

/// A fungible holding whose balance is a starting amount plus its transactions.
protocol LedgerHolding: Identifiable<UUID> {
    var startingAmount: Double { get set }
    var transactions: [AssetTransaction] { get set }
}

extension LedgerHolding {
    var balance: Double {
        transactions.reduce(startingAmount) { $0 + $1.signedQuantity }
    }

    /// Transactions oldest first, each with the balance right after it.
    var ledger: [(transaction: AssetTransaction, balanceAfter: Double)] {
        var running = startingAmount
        return transactions.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map { entry in
                running += entry.element.signedQuantity
                return (entry.element, running)
            }
    }
}

struct CryptoHolding: LedgerHolding, Codable, Hashable {
    var id = UUID()
    var coinID: String          // CoinGecko id, e.g. "bitcoin"
    var symbol: String
    var name: String
    var imageURL: URL?
    var startingAmount: Double
    var label: String = ""      // where it's held, e.g. "Ledger"
    var transactions: [AssetTransaction] = []
    var startingPrice: Double?          // average buy price of the starting balance, for profit
    var startingPriceCurrency: String?
}

struct CashHolding: LedgerHolding, Codable, Hashable {
    var id = UUID()
    var currency: String        // ISO 4217 code
    var startingAmount: Double
    var label: String = ""
    var transactions: [AssetTransaction] = []
}

// Files written before transactions existed stored the balance as "amount".
private enum LegacyKeys: String, CodingKey { case amount }

extension CryptoHolding {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        coinID = try c.decode(String.self, forKey: .coinID)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        startingAmount = try c.decodeIfPresent(Double.self, forKey: .startingAmount)
            ?? decoder.container(keyedBy: LegacyKeys.self).decode(Double.self, forKey: .amount)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        transactions = try c.decodeIfPresent([AssetTransaction].self, forKey: .transactions) ?? []
        startingPrice = try c.decodeIfPresent(Double.self, forKey: .startingPrice)
        startingPriceCurrency = try c.decodeIfPresent(String.self, forKey: .startingPriceCurrency)
    }
}

extension CashHolding {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        currency = try c.decode(String.self, forKey: .currency)
        startingAmount = try c.decodeIfPresent(Double.self, forKey: .startingAmount)
            ?? decoder.container(keyedBy: LegacyKeys.self).decode(Double.self, forKey: .amount)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        transactions = try c.decodeIfPresent([AssetTransaction].self, forKey: .transactions) ?? []
    }
}

struct AssetTransaction: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case buy, sell, receive, send
        var id: String { rawValue }

        var isInflow: Bool { self == .buy || self == .receive }
        /// Buys and sells record their price; receives can carry a cost (e.g. coins moved in).
        var hasPrice: Bool { self != .send }

        func title(cash: Bool) -> String {
            switch self {
            case .buy: "Buy"
            case .sell: "Sell"
            case .receive: cash ? "Deposit" : "Receive"
            case .send: cash ? "Withdrawal" : "Send"
            }
        }

        static func options(cash: Bool) -> [Kind] { cash ? [.receive, .send] : allCases }
    }

    var id = UUID()
    var kind: Kind
    var date: Date
    var quantity: Double        // always positive; `kind` gives the direction
    var price: Double?          // per unit: buy/sell price, or cost of a receive
    var priceCurrency: String?
    var note: String = ""

    var signedQuantity: Double { kind.isInflow ? quantity : -quantity }
    var total: Double? { price.map { $0 * quantity } }
}

/// Points at one fungible holding, e.g. for navigation or adding a transaction.
enum HoldingRef: Hashable {
    case crypto(UUID)
    case cash(UUID)
}

struct NFTHolding: Identifiable, Codable, Hashable {
    var id = UUID()
    var collection: NFTCollection
    var tokenID: Int
}

enum NFTCollection: String, Codable, CaseIterable, Identifiable {
    case miladyMaker = "milady-maker"
    case remilioBabies = "redacted-remilio-babies"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .miladyMaker: "Milady Maker"
        case .remilioBabies: "Remilio Babies"
        }
    }

    var tokenName: String {
        switch self {
        case .miladyMaker: "Milady"
        case .remilioBabies: "Remilio"
        }
    }

    var contract: String {
        switch self {
        case .miladyMaker: "0x5af0d9827e0c53e4799bb226655a1de152a425a5"
        case .remilioBabies: "0xd3d9ddd0cf0a5f0bfb8f7fceae075df687eaebab"
        }
    }

    func imageURL(token: Int) -> URL {
        switch self {
        case .miladyMaker: URL(string: "https://www.miladymaker.net/milady/\(token).png")!
        case .remilioBabies: URL(string: "https://remilio.org/remilio/\(token).png")!
        }
    }

    func marketplaceURL(token: Int) -> URL {
        URL(string: "https://opensea.io/item/ethereum/\(contract)/\(token)")!
    }
}

struct Portfolio: Codable, Equatable {
    var version = 1
    var crypto: [CryptoHolding] = []
    var cash: [CashHolding] = []
    var nfts: [NFTHolding] = []

    init() {}

    // Tolerate missing sections so older/hand-edited files still load.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        crypto = try c.decodeIfPresent([CryptoHolding].self, forKey: .crypto) ?? []
        cash = try c.decodeIfPresent([CashHolding].self, forKey: .cash) ?? []
        nfts = try c.decodeIfPresent([NFTHolding].self, forKey: .nfts) ?? []
    }

    var isEmpty: Bool { crypto.isEmpty && cash.isEmpty && nfts.isEmpty }
}

// MARK: - Market data (all prices in USD)

struct CoinQuote: Codable, Hashable {
    var price: Double
    var change24h: Double?      // percent
    var sparkline: [Double]     // last 7 days, hourly
    var imageURL: URL?
}

struct NFTQuote: Codable, Hashable {
    var floorETH: Double
    var floorUSD: Double
    var change24h: Double?      // percent, USD
    var imageURL: URL?
}

struct PricePoint: Codable, Hashable {
    var date: Date
    var price: Double           // USD
}

struct MarketData: Codable {
    var coins: [String: CoinQuote] = [:]
    var nfts: [String: NFTQuote] = [:]
    var usdRates: [String: Double] = ["USD": 1]  // 1 USD = x units of currency
    var updated: Date?
    /// Daily prices per coin for the YTD and 1Y chart ranges, oldest first.
    var daily: [String: [PricePoint]] = [:]
    var dailyUpdated: [String: Date] = [:]

    init() {}

    // Tolerate caches written by older versions.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent([String: CoinQuote].self, forKey: .coins) ?? [:]
        nfts = try c.decodeIfPresent([String: NFTQuote].self, forKey: .nfts) ?? [:]
        usdRates = try c.decodeIfPresent([String: Double].self, forKey: .usdRates) ?? ["USD": 1]
        updated = try c.decodeIfPresent(Date.self, forKey: .updated)
        daily = try c.decodeIfPresent([String: [PricePoint]].self, forKey: .daily) ?? [:]
        dailyUpdated = try c.decodeIfPresent([String: Date].self, forKey: .dailyUpdated) ?? [:]
    }
}

// MARK: - Preferences

enum Pref {
    static let baseCurrency = "baseCurrency"
    static let hideBalances = "hideBalances"
    static let refreshMinutes = "refreshMinutes"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let menuBarShowsTotal = "menuBarShowsTotal"
    static let apiKey = "coingeckoAPIKey"
    static let lastSection = "lastSection"
    static let chartRange = "chartRange"
    static let secondaryCurrency = "secondaryCurrency"  // clicking net worth switches to it
    static let showsSecondaryCurrency = "showsSecondaryCurrency"
    static let storeInICloud = "storeInICloud"          // what the user chose in Settings
    static let portfolioInICloud = "portfolioInICloud"  // the real copy has moved to iCloud Drive

    static var defaultCurrency: String { Locale.current.currency?.identifier ?? "USD" }
    static var defaultSecondaryCurrency: String { defaultCurrency == "USD" ? "EUR" : "USD" }

    /// The app's preferences. UI tests get a fresh throwaway suite so real settings are never touched.
    /// (UserDefaults is thread-safe; it just isn't annotated Sendable.)
    nonisolated(unsafe) static let defaults: UserDefaults = {
        #if DEBUG
        if TestMode.isActive {
            UserDefaults.standard.removePersistentDomain(forName: TestMode.defaultsSuite)
            let suite = UserDefaults(suiteName: TestMode.defaultsSuite)!
            suite.set("USD", forKey: baseCurrency)
            return suite
        }
        #endif
        return .standard
    }()
}
