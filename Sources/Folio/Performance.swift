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
    /// Average cost per coin still held.
    let averageCost: Double?
    /// The starting balance has no price of its own, so it's valued at the average of the logged buys.
    let isEstimated: Bool

    var total: Double { realized + unrealized }
    var percent: Double? { invested > 0 ? total / invested * 100 : nil }

    /// nil when it can't be known: the starting balance has no price and there are no priced buys
    /// to estimate it from, a buy or sell has no price, or there's no current price. `convert` turns
    /// an amount in a currency into the display currency (nil currency means it's already in it).
    init?(holding: CryptoHolding, currentValue: Double?, convert: (Double, String?) -> Double?) {
        guard let currentValue else { return nil }
        var quantity = holding.startingAmount
        var cost = 0.0
        var isEstimated = false
        if holding.startingAmount > 0 {
            if let price = holding.startingPrice,
               let value = convert(price * holding.startingAmount, holding.startingPriceCurrency) {
                cost = value
            } else if let average = Self.averageBuyPrice(holding, convert: convert) {
                cost = average * holding.startingAmount
                isEstimated = true
            } else {
                return nil
            }
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
        self.averageCost = quantity > 0 ? max(cost, 0) / quantity : nil
        self.isEstimated = isEstimated
    }

    /// Average price paid across the holding's priced buys, in the display currency.
    private static func averageBuyPrice(_ holding: CryptoHolding, convert: (Double, String?) -> Double?) -> Double? {
        var spent = 0.0
        var bought = 0.0
        for transaction in holding.transactions where transaction.kind == .buy {
            guard let total = transaction.total, let value = convert(total, transaction.priceCurrency) else { continue }
            spent += value
            bought += transaction.quantity
        }
        return bought > 0 ? spent / bought : nil
    }
}
