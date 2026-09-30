import Foundation

/// What the app hands to the widget: already-valued numbers, so the widget needs no network access.
struct WidgetSnapshot: Codable, Equatable {
    struct Slice: Codable, Equatable {
        var category: String    // "crypto" | "cash" | "nfts"
        var value: Double
    }

    var currency: String
    var total: Double
    var change24h: Double
    var change24hPercent: Double?
    var slices: [Slice]
    var history: [Double]       // last 7 days, oldest first
    var hidden: Bool
    var updated: Date

    static let fileName = "widget.json"

    /// ~/Library/Application Support/Folio, resolved from the real home directory so it
    /// also works inside the sandboxed widget (whose NSHomeDirectory is its container).
    static var directory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appending(path: "Library/Application Support/Folio", directoryHint: .isDirectory)
    }

    static func load(from directory: URL = directory) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appending(path: fileName)) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write(to directory: URL) throws {
        try Self.encoder.encode(self).write(to: directory.appending(path: Self.fileName), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
