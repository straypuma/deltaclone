import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension AssetCategory {
    var color: Color {
        switch self {
        case .crypto: .orange
        case .cash: .teal
        case .nfts: .pink
        }
    }
}

// MARK: - Table cells

extension View {
    /// Fills the whole table cell so a click or double-click anywhere in the row registers,
    /// not just on the text itself.
    func tableCell(_ alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .contentShape(.rect)
    }
}

// MARK: - Change indicator

struct ChangeLabel: View {
    let percent: Double?
    var amount: Double? = nil
    var currency: String = "USD"

    var body: some View {
        HStack(spacing: 4) {
            if let percent, percent != 0 {
                Image(systemName: percent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .imageScale(.small)
            }
            if let amount {
                Text(Format.signedMoney(amount, currency)).privacySensitive()
            }
            Text(amount == nil ? Format.percent(percent) : "(\(Format.percent(percent)))")
        }
        .monospacedDigit()
        .foregroundStyle(color)
    }

    private var color: Color {
        guard let percent, percent != 0 else { return .secondary }
        return percent > 0 ? .green : .red
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        SparklineShape(values: values)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private var tint: Color {
        guard let first = values.first, let last = values.last else { return .secondary }
        return last >= first ? .green : .red
    }
}

// MARK: - Asset icons

struct AssetIcon: View {
    let icon: AssetLine.Icon
    var size: CGFloat = 28

    var body: some View {
        switch icon {
        case .remote(let url):
            RemoteImage(url: url, maxPixel: Int(size * 3))
                .frame(width: size, height: size)
                .clipShape(.circle)
        case .currency(let code):
            CurrencyBadge(code: code, size: size)
        }
    }
}

struct CurrencyBadge: View {
    let code: String
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(AssetCategory.cash.color.opacity(0.15))
            if let flag = Currency.flag(code) {
                Text(flag).font(.system(size: size * 0.62))
            } else {
                Text(code.prefix(1)).font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(AssetCategory.cash.color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Summary header used atop each section

struct SummaryHeader: View {
    let title: String
    let value: Double
    let currency: String
    var change: Double? = nil
    var changePercent: Double? = nil
    var detail: String? = nil
    /// All-time profit, shown under today's change when known.
    var allTime: (amount: Double, percent: Double?)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(Format.money(value, currency))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .privacySensitive()
                    .accessibilityIdentifier("section-total")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let changePercent {
                    ChangeLabel(percent: changePercent, amount: change, currency: currency)
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    if let allTime {
                        ChangeLabel(percent: allTime.percent ?? 0, amount: allTime.amount, currency: currency)
                            .padding(.top, 4)
                        Text("All time").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let detail {
                    Text(detail).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Remote images (downsampled + cached on disk)

struct RemoteImage: View {
    let url: URL?
    var maxPixel = 96
    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let image = loaded ?? url.flatMap({ ImageLoader.cached($0, maxPixel: maxPixel) }) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            guard let url else { return }
            loaded = await ImageLoader.load(url, maxPixel: maxPixel)
        }
    }
}

@MainActor
enum ImageLoader {
    private static var memory: [String: NSImage] = [:]

    static func cached(_ url: URL, maxPixel: Int) -> NSImage? {
        memory[key(url, maxPixel)]
    }

    static func load(_ url: URL, maxPixel: Int) async -> NSImage? {
        let key = key(url, maxPixel)
        if let hit = memory[key] { return hit }
        let file = cacheDirectory.appending(path: key)
        let data = await Task.detached(priority: .utility) { () -> Data? in
            if let data = try? Data(contentsOf: file) { return data }
            guard let (raw, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let thumb = thumbnail(raw, maxPixel: maxPixel) else { return nil }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? thumb.write(to: file, options: .atomic)
            return thumb
        }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        memory[key] = image
        return image
    }

    nonisolated private static let cacheDirectory =
        URL.cachesDirectory.appending(path: "Folio/images", directoryHint: .isDirectory)

    nonisolated private static func key(_ url: URL, _ maxPixel: Int) -> String {
        let safe = url.absoluteString.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return String(String(safe).suffix(120)) + "-\(maxPixel).png"
    }

    nonisolated private static func thumbnail(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
