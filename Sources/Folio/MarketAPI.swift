import Foundation

enum MarketError: LocalizedError {
    case rateLimited
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited: "CoinGecko rate limit reached"
        case .http(let code): "Server returned \(code)"
        }
    }
}

struct CoinSearchResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let marketCapRank: Int?
    let large: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, large
        case marketCapRank = "market_cap_rank"
    }
}

/// CoinGecko for crypto + NFT floors, open.er-api.com for fiat rates. No key required.
struct MarketAPI: Sendable {
    var apiKey: String?

    func markets(ids: [String]) async throws -> [String: CoinQuote] {
        guard !ids.isEmpty else { return [:] }
        #if DEBUG
        if TestMode.stubsMarket { return MarketFixtures.markets(ids) }
        #endif
        struct Coin: Decodable {
            let id: String
            let currentPrice: Double?
            let priceChangePercentage24h: Double?
            let image: URL?
            let sparklineIn7d: Sparkline?
            struct Sparkline: Decodable { let price: [Double?]? }

            enum CodingKeys: String, CodingKey {
                case id, image
                case currentPrice = "current_price"
                case priceChangePercentage24h = "price_change_percentage_24h"
                case sparklineIn7d = "sparkline_in_7d"
            }
        }
        var quotes: [String: CoinQuote] = [:]
        // 250 ids per page is CoinGecko's max.
        for chunk in stride(from: 0, to: ids.count, by: 250).map({ Array(ids[$0..<min($0 + 250, ids.count)]) }) {
            let data = try await coingecko("coins/markets", [
                .init(name: "vs_currency", value: "usd"),
                .init(name: "ids", value: chunk.joined(separator: ",")),
                .init(name: "per_page", value: "250"),
                .init(name: "sparkline", value: "true"),
            ])
            for coin in try JSONDecoder().decode([Coin].self, from: data) {
                guard let price = coin.currentPrice else { continue }
                var last = price
                let spark = (coin.sparklineIn7d?.price ?? []).map { p -> Double in
                    if let p { last = p }
                    return p ?? last
                }
                quotes[coin.id] = CoinQuote(price: price, change24h: coin.priceChangePercentage24h,
                                            sparkline: spark, imageURL: coin.image)
            }
        }
        return quotes
    }

    func nftFloor(_ collection: NFTCollection) async throws -> NFTQuote {
        #if DEBUG
        if TestMode.stubsMarket { return MarketFixtures.nftFloor(collection) }
        #endif
        struct Response: Decodable {
            let floorPrice: Price?
            let floorPriceInUsd24hPercentageChange: Double?
            let image: Image?
            struct Price: Decodable {
                let nativeCurrency: Double?
                let usd: Double?
                enum CodingKeys: String, CodingKey { case usd, nativeCurrency = "native_currency" }
            }
            struct Image: Decodable {
                let small2x: URL?
                let small: URL?
                enum CodingKeys: String, CodingKey { case small, small2x = "small_2x" }
            }

            enum CodingKeys: String, CodingKey {
                case image
                case floorPrice = "floor_price"
                case floorPriceInUsd24hPercentageChange = "floor_price_in_usd_24h_percentage_change"
            }
        }
        let data = try await coingecko("nfts/\(collection.rawValue)", [])
        let r = try JSONDecoder().decode(Response.self, from: data)
        return NFTQuote(floorETH: r.floorPrice?.nativeCurrency ?? 0,
                        floorUSD: r.floorPrice?.usd ?? 0,
                        change24h: r.floorPriceInUsd24hPercentageChange,
                        imageURL: r.image?.small2x ?? r.image?.small)
    }

    /// Daily USD prices for the past 365 days (the free API's limit).
    func dailyHistory(id: String) async throws -> [PricePoint] {
        #if DEBUG
        if TestMode.stubsMarket { return MarketFixtures.daily(id) }
        #endif
        struct Response: Decodable { let prices: [[Double]] }
        let data = try await coingecko("coins/\(id)/market_chart", [
            .init(name: "vs_currency", value: "usd"),
            .init(name: "days", value: "365"),
            .init(name: "interval", value: "daily"),
        ])
        return try JSONDecoder().decode(Response.self, from: data).prices.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return PricePoint(date: Date(timeIntervalSince1970: pair[0] / 1000), price: pair[1])
        }
    }

    func exchangeRates() async throws -> [String: Double] {
        #if DEBUG
        if TestMode.stubsMarket { return MarketFixtures.usdRates }
        #endif
        struct Response: Decodable { let result: String; let rates: [String: Double] }
        let request = URLRequest(url: URL(string: "https://open.er-api.com/v6/latest/USD")!, timeoutInterval: 20)
        let r = try JSONDecoder().decode(Response.self, from: try await fetch(request))
        return r.rates
    }

    func search(_ query: String) async throws -> [CoinSearchResult] {
        #if DEBUG
        if TestMode.stubsMarket { return MarketFixtures.search(query) }
        #endif
        struct Response: Decodable { let coins: [CoinSearchResult] }
        let data = try await coingecko("search", [.init(name: "query", value: query)])
        return try JSONDecoder().decode(Response.self, from: data).coins
    }

    // MARK: Plumbing

    private func coingecko(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-cg-demo-api-key")
        }
        return try await fetch(request)
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 429: throw MarketError.rateLimited
        default: throw MarketError.http(status)
        }
    }
}
