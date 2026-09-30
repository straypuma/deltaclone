import SwiftUI
import WidgetKit

@main
struct FolioWidgets: WidgetBundle {
    var body: some Widget {
        NetWorthWidget()
    }
}

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetWorth", provider: Provider()) { entry in
            NetWorthView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Net Worth")
        .description("Your total portfolio value and how it moved today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Folio pushes fresh numbers and reloads the widget itself; this just reads them.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        completion(Entry(date: .now, snapshot: context.isPreview ? snapshot ?? .sample : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Views

struct NetWorthView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, snapshot.slices.contains(where: { $0.value > 0 }) {
            switch family {
            case .systemMedium: medium(snapshot)
            default: summary(snapshot)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Folio", systemImage: "chart.pie.fill").font(.caption.weight(.semibold))
                Spacer()
                Text("Add holdings in Folio to see your net worth here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func summary(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Net Worth", systemImage: "chart.pie.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(s.hidden ? "••••••" : money(s.total, s.currency))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            change(s)
            Text("Updated \(s.updated.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            summary(s)
            VStack(alignment: .leading, spacing: 8) {
                if s.history.count > 1 {
                    SparklineShape(values: s.history)
                        .stroke(tint(s), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(maxHeight: .infinity)
                }
                ForEach(s.slices.filter { $0.value > 0 }, id: \.category) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(color(slice.category)).frame(width: 7, height: 7)
                        Text(title(slice.category)).font(.caption)
                        Spacer(minLength: 4)
                        Text(s.hidden ? "•••" : share(slice.value, of: s.total))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func change(_ s: WidgetSnapshot) -> some View {
        if let pct = s.change24hPercent {
            let up = pct >= 0
            HStack(spacing: 3) {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").imageScale(.small)
                Text((pct / 100).formatted(.percent.precision(.fractionLength(2))))
                Text("today").foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(pct == 0 ? .secondary : up ? Color.green : Color.red)
        }
    }

    private func tint(_ s: WidgetSnapshot) -> Color {
        (s.history.last ?? 0) >= (s.history.first ?? 0) ? .green : .red
    }

    private func money(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(value >= 100_000 ? 0 : 2)))
    }

    private func share(_ value: Double, of total: Double) -> String {
        total > 0 ? (value / total).formatted(.percent.precision(.fractionLength(0))) : "—"
    }

    private func title(_ category: String) -> String {
        switch category {
        case "crypto": "Crypto"
        case "cash": "Cash"
        default: "NFTs"
        }
    }

    private func color(_ category: String) -> Color {
        switch category {
        case "crypto": .orange
        case "cash": .teal
        default: .pink
        }
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        currency: "USD", total: 81_326, change24h: 412, change24hPercent: 0.51,
        slices: [.init(category: "crypto", value: 58_600), .init(category: "cash", value: 17_060),
                 .init(category: "nfts", value: 5_660)],
        history: (0..<56).map { 80_000 + 1_300 * sin(Double($0) / 6) + Double($0) * 20 },
        hidden: false, updated: .now
    )
}
