#if DEBUG
import Foundation

/// Hooks for the UI tests. Compiled into Debug builds only.
///
/// - `FOLIO_DATA_DIR`: store the portfolio there and use throwaway preferences,
///   so tests never touch real data.
/// - `FOLIO_STUB_MARKET=1`: answer market requests with the fixed prices below.
/// - `FOLIO_ICLOUD_ROOT`: a folder to treat as iCloud Drive.
enum TestMode {
    static let dataDirectory: URL? = ProcessInfo.processInfo.environment["FOLIO_DATA_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
    static let stubsMarket = ProcessInfo.processInfo.environment["FOLIO_STUB_MARKET"] == "1"
    /// Stands in for iCloud Drive (`FOLIO_ICLOUD_ROOT`); without it, tests run with iCloud off.
    static let iCloudRoot: URL? = ProcessInfo.processInfo.environment["FOLIO_ICLOUD_ROOT"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
    static var isActive: Bool { dataDirectory != nil }

    static let defaultsSuite = "app.folio.Folio.uitests"
}

enum MarketFixtures {
    static let coins: [(id: String, name: String, symbol: String, rank: Int, price: Double)] = [
        ("bitcoin", "Bitcoin", "BTC", 1, 100_000),
        ("ethereum", "Ethereum", "ETH", 2, 4_000),
        ("solana", "Solana", "SOL", 5, 200),
    ]

    static let usdRates: [String: Double] = ["USD": 1, "EUR": 0.9, "GBP": 0.8, "JPY": 150, "CHF": 0.85]

    static func markets(_ ids: [String]) -> [String: CoinQuote] {
        var quotes: [String: CoinQuote] = [:]
        for coin in coins where ids.contains(coin.id) {
            let spark = (0..<168).map { coin.price * (0.95 + 0.05 * Double($0) / 167) }
            quotes[coin.id] = CoinQuote(price: coin.price, change24h: 2, sparkline: spark, imageURL: nil)
        }
        return quotes
    }

    static func nftFloor(_ collection: NFTCollection) -> NFTQuote {
        switch collection {
        case .miladyMaker: NFTQuote(floorETH: 1, floorUSD: 4_000, change24h: 1, imageURL: nil)
        case .remilioBabies: NFTQuote(floorETH: 0.1, floorUSD: 400, change24h: -2, imageURL: nil)
        }
    }

    static func search(_ query: String) -> [CoinSearchResult] {
        coins.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.symbol.localizedCaseInsensitiveContains(query) }
            .map { CoinSearchResult(id: $0.id, name: $0.name, symbol: $0.symbol, marketCapRank: $0.rank, large: nil) }
    }
}
#endif
