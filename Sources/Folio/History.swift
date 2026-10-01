import Foundation

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "24H", week = "7D", yearToDate = "YTD", year = "1Y"
    var id: String { rawValue }

    /// 24H and 7D use the hourly 7-day prices; the rest use cached daily prices.
    var usesDailyPrices: Bool { self != .day && self != .week }

    var label: String {
        switch self {
        case .day: "Today"
        case .week: "Past week"
        case .yearToDate: "Year to date"
        case .year: "Past year"
        }
    }

    func start(before now: Date) -> Date? {
        let calendar = Calendar.current
        return switch self {
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .yearToDate: calendar.date(from: calendar.dateComponents([.year], from: now))
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        }
    }
}

extension Valuation {
    /// Net worth over `range`: what you held at each moment (transactions applied on their dates,
    /// starting balances held throughout) at that moment's prices. Cash uses today's exchange
    /// rates and NFTs today's floor in ETH. The last point is today's actual total.
    func history(_ range: ChartRange) -> [HistoryPoint] {
        guard let usdToBase else { return [] }
        let now = market.updated ?? .now

        var seriesCache: [String: [PricePoint]] = [:]
        func series(_ id: String) -> [PricePoint] {
            if let cached = seriesCache[id] { return cached }
            let points: [PricePoint]
            if range.usesDailyPrices {
                points = market.daily[id] ?? []
            } else {
                let spark = market.coins[id]?.sparkline ?? []
                points = spark.enumerated().map { index, price in
                    PricePoint(date: now.addingTimeInterval(-Double(spark.count - 1 - index) * 3600), price: price)
                }
            }
            seriesCache[id] = points
            return points
        }

        // Bitcoin is always fetched, so its timestamps make a good timeline.
        let start = range.start(before: now) ?? .distantPast
        let reference = series("bitcoin").isEmpty
            ? portfolio.crypto.map { series($0.coinID) }.first { !$0.isEmpty } ?? []
            : series("bitcoin")
        let timeline = reference.map(\.date).filter { $0 >= start && $0 < now.addingTimeInterval(-60) }
        guard !timeline.isEmpty else { return [] }

        let nftCount = Dictionary(grouping: portfolio.nfts, by: \.collection).mapValues(\.count)
        let cashUnits = Dictionary(uniqueKeysWithValues: cash.map { ($0.id, $0.unitValue ?? 0) })

        var points = timeline.map { date -> HistoryPoint in
            var usd = 0.0
            for holding in portfolio.crypto {
                let quantity = Self.quantity(of: holding, at: date)
                guard quantity != 0 else { continue }
                let price = Self.price(in: series(holding.coinID), at: date) ?? market.coins[holding.coinID]?.price ?? 0
                usd += quantity * price
            }
            if let eth = Self.price(in: series("ethereum"), at: date) ?? market.coins["ethereum"]?.price {
                for (collection, count) in nftCount {
                    usd += Double(count) * (market.nfts[collection.rawValue]?.floorETH ?? 0) * eth
                }
            }
            let cashValue = portfolio.cash.reduce(0) { $0 + Self.quantity(of: $1, at: date) * (cashUnits[$1.id] ?? 0) }
            return HistoryPoint(date: date, value: usd * usdToBase + cashValue,
                                btcPrice: Self.price(in: series("bitcoin"), at: date).map { $0 * usdToBase })
        }
        points.append(HistoryPoint(date: now, value: total, btcPrice: btcPrice))
        return points
    }

    private static func quantity(of holding: some LedgerHolding, at date: Date) -> Double {
        holding.transactions.reduce(holding.startingAmount) { $1.date <= date ? $0 + $1.signedQuantity : $0 }
    }

    /// The latest price at or before `date` (series are oldest first).
    private static func price(in series: [PricePoint], at date: Date) -> Double? {
        var low = 0, high = series.count - 1, found: Double?
        while low <= high {
            let mid = (low + high) / 2
            if series[mid].date <= date { found = series[mid].price; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }
}
