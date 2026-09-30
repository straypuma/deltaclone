import Foundation

enum Format {
    static func money(_ value: Double?, _ code: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: code))
    }

    static func wholeMoney(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    static func compactMoney(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).notation(.compactName).precision(.significantDigits(1...3)))
    }

    static func signedMoney(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).sign(strategy: .always(showZero: false)))
    }

    /// Prices below 1 keep significant digits so small-cap coins don't round to 0.00.
    static func price(_ value: Double?, _ code: String) -> String {
        guard let value else { return "—" }
        if value == 0 || abs(value) >= 1 { return value.formatted(.currency(code: code)) }
        return value.formatted(.currency(code: code).precision(.significantDigits(2...4)))
    }

    static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)))
    }

    static func signedAmount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)).sign(strategy: .always()))
    }

    static func editableAmount(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...12)))
    }

    static func percent(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        return (pct / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
    }

    static func share(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0)))
    }

    static func btc(_ value: Double) -> String {
        let precision: NumberFormatStyleConfiguration.Precision = value >= 1 ? .fractionLength(4) : .significantDigits(4)
        return value.formatted(.number.precision(precision)) + " BTC"
    }

    static func eth(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...4))) + " ETH"
    }

    /// Accepts locale formatting ("1,234.5" / "1.234,5") as well as a plain "1234.5".
    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard !trimmed.isEmpty else { return nil }
        if let plain = Double(trimmed) { return plain }
        if let localized = try? Double(trimmed, format: .number) { return localized }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

enum Currency {
    static let common = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY", "HKD", "SGD", "KRW", "INR", "BRL", "MXN", "AED"]

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func flag(_ code: String) -> String? {
        let region = code.prefix(2).uppercased()
        guard region == "EU" || Locale.Region.isoRegions.contains(Locale.Region(region)) else { return nil }
        return region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }

    /// Currencies we can value: anything with a known exchange rate that the system can name.
    static func available(rates: [String: Double]) -> [String] {
        let codes = Set(rates.keys).union(common)
        return codes.filter { Locale.current.localizedString(forCurrencyCode: $0) != nil }
            .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }
}
