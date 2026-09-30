import Foundation

/// Profit and loss for one crypto holding using the average-cost method, in the display currency.
struct Performance {
    /// Everything put in: the starting balance at its average price, buys, and costed receives.
    let invested: Double
    /// What the coins still held cost.
    let costBasis: Double
    /// Gains locked in by sells (sale price minus average cost).
    let realized: Double
    /// Today's value of what's held minus what it cost.
    let unrealized: Double

    var total: Double { realized + unrealized }
    var percent: Double? { invested > 0 ? total / invested * 100 : nil }

    /// nil when it can't be known: the starting balance has no average price, a buy or sell has
    /// no price, or there's no current price. `convert` turns an amount in a currency into the
    /// display currency (nil currency means it's already in it).
    init?(holding: CryptoHolding, currentValue: Double?, convert: (Double, String?) -> Double?) {
        guard let currentValue else { return nil }
        var quantity = holding.startingAmount
        var cost = 0.0
        if holding.startingAmount > 0 {
            guard let price = holding.startingPrice,
                  let value = convert(price * holding.startingAmount, holding.startingPriceCurrency) else { return nil }
            cost = value
        }
        var invested = cost
        var realized = 0.0

        for (transaction, _) in holding.ledger {
            let value = transaction.total.flatMap { convert($0, transaction.priceCurrency) }
            switch transaction.kind {
            case .buy:
                guard let value else { return nil }
                quantity += transaction.quantity
                cost += value
                invested += value
            case .receive:  // no price: free coins, e.g. an airdrop
                quantity += transaction.quantity
                cost += value ?? 0
                invested += value ?? 0
            case .sell, .send:
                let averageCost = quantity > 0 ? cost / quantity : 0
                let removedCost = averageCost * min(transaction.quantity, quantity)
                if transaction.kind == .sell {
                    guard let value else { return nil }
                    realized += value - removedCost
                }
                quantity -= transaction.quantity
                cost -= removedCost
            }
        }

        self.invested = invested
        self.costBasis = max(cost, 0)
        self.realized = realized
        self.unrealized = currentValue - max(cost, 0)
    }
}
