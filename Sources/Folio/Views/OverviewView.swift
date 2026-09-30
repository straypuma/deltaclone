import Charts
import SwiftUI

struct OverviewView: View {
    let valuation: Valuation
    @Environment(Navigator.self) private var navigator
    @AppStorage(Pref.hideBalances, store: Pref.defaults) private var hideBalances = false
    @State private var range: ChartRange = .week
    @State private var hoverDate: Date?

    enum ChartRange: String, CaseIterable, Identifiable {
        case day = "24H", week = "7D"
        var id: String { rawValue }
    }

    var body: some View {
        if valuation.isEmpty {
            ContentUnavailableView {
                Label("Nothing Tracked Yet", systemImage: "chart.pie")
            } description: {
                Text("Add crypto, cash balances or NFTs to see your net worth.")
            } actions: {
                HStack {
                    Button("Add Crypto") { navigator.sheet = .crypto(nil) }
                    Button("Add Cash") { navigator.sheet = .cash(nil) }
                    Button("Add NFT") { navigator.sheet = .nft(nil) }
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if points.count > 1 { chart }
                    HStack(alignment: .top, spacing: 20) {
                        allocation
                        holdings
                    }
                    footer
                }
                .padding(24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Header

    private var hovered: HistoryPoint? {
        guard let hoverDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(hoverDate)) < abs($1.date.timeIntervalSince(hoverDate)) }
    }

    private var points: [HistoryPoint] {
        range == .week ? valuation.history : Array(valuation.history.suffix(25))
    }

    private var rangeChange: (amount: Double, percent: Double?)? {
        guard range == .week, let first = points.first, let last = points.last else { return nil }
        return (last.value - first.value, first.value > 0 ? (last.value - first.value) / first.value * 100 : nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hovered.map { $0.date.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()) } ?? "Net Worth")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Format.money(hovered?.value ?? valuation.total, valuation.base))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .privacySensitive()
            if let (amount, percent) = rangeChange {
                HStack(spacing: 6) {
                    ChangeLabel(percent: percent, amount: amount, currency: valuation.base)
                    Text("Past week").foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    ChangeLabel(percent: valuation.change24hPercent, amount: valuation.change24h, currency: valuation.base)
                    Text("Today").foregroundStyle(.secondary)
                }
            }
            if let profit = valuation.cryptoProfit {
                HStack(spacing: 6) {
                    ChangeLabel(percent: profit.percent ?? 0, amount: profit.total, currency: valuation.base)
                    Text("All-time crypto profit").foregroundStyle(.secondary)
                    if profit.includesEstimates {
                        Text("· includes estimates")
                            .foregroundStyle(.tertiary)
                            .help("Some starting balances are valued at the average of their logged buys")
                    }
                    if valuation.holdingsWithoutCost > 0 {
                        Text("· \(valuation.holdingsWithoutCost) without a buy price")
                            .foregroundStyle(.tertiary)
                            .help("Add an average buy price to those holdings to include them")
                    }
                }
            }
        }
        .animation(.snappy, value: valuation.total)
    }

    // MARK: Chart

    private var chart: some View {
        let values = points.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, hi * 0.001, 0.01)
        let domain = (lo - pad)...(hi + pad)
        let tint: Color = (values.last ?? 0) >= (values.first ?? 0) ? .green : .red

        return GroupBox {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Time", point.date),
                             yStart: .value("Base", domain.lowerBound),
                             yEnd: .value("Value", point.value))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.22), tint.opacity(0.0)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let hovered {
                    RuleMark(x: .value("Time", hovered.date))
                        .foregroundStyle(.secondary.opacity(0.5))
                    PointMark(x: .value("Time", hovered.date), y: .value("Value", hovered.value))
                        .foregroundStyle(tint)
                        .symbolSize(60)
                }
            }
            .chartYScale(domain: domain)
            .chartXSelection(value: $hoverDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 6)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let v = value.as(Double.self), !hideBalances {
                            Text(Format.compactMoney(v, valuation.base))
                        }
                    }
                }
            }
            .frame(height: 230)
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Performance")
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: Allocation

    private var allocation: some View {
        let slices = AssetCategory.allCases.filter { valuation.total($0) > 0 }
        return GroupBox("Allocation") {
            VStack(spacing: 16) {
                Chart(slices) { category in
                    SectorMark(angle: .value("Value", valuation.total(category)),
                               innerRadius: .ratio(0.66), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(category.color)
                }
                .frame(height: 160)
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text("\(valuation.assets.count)").font(.title2.weight(.semibold)).monospacedDigit()
                        Text(valuation.assets.count == 1 ? "asset" : "assets").font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(AssetCategory.allCases) { category in
                        Button { navigator.selection = SidebarItem(rawValue: category.rawValue) } label: {
                            HStack {
                                Circle().fill(category.color).frame(width: 8, height: 8)
                                Text(category.title)
                                Spacer()
                                Text(Format.money(valuation.total(category), valuation.base))
                                    .monospacedDigit().privacySensitive()
                                Text(share(valuation.total(category)))
                                    .monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 300)
    }

    // MARK: Holdings

    private var holdings: some View {
        GroupBox("Holdings") {
            VStack(spacing: 0) {
                ForEach(Array(valuation.assets.enumerated()), id: \.element.id) { index, asset in
                    if index > 0 { Divider().padding(.leading, 44) }
                    HStack(spacing: 12) {
                        AssetIcon(icon: asset.icon, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.title).fontWeight(.medium)
                            Text(asset.subtitle).font(.caption).foregroundStyle(.secondary)
                                .privacySensitive()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.money(asset.value, valuation.base))
                                .monospacedDigit().fontWeight(.medium).privacySensitive()
                            HStack(spacing: 6) {
                                if asset.change24h != nil {
                                    ChangeLabel(percent: asset.change24h).font(.caption)
                                }
                                Text(share(asset.value)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("Prices by")
            Link("CoinGecko", destination: URL(string: "https://www.coingecko.com")!)
            Text("· Exchange rates by")
            Link("ExchangeRate-API", destination: URL(string: "https://www.exchangerate-api.com")!)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }

    private func share(_ value: Double) -> String {
        valuation.total > 0 ? Format.share(value / valuation.total) : "—"
    }
}
