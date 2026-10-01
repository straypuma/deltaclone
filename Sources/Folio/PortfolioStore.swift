import AppKit
import Foundation
import WidgetKit

/// Owns the portfolio, persists it as plain JSON, and keeps market data fresh.
@MainActor @Observable
final class PortfolioStore {
    private(set) var portfolio = Portfolio()
    private(set) var market = MarketData()
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    var dataWarning: String?
    /// Where portfolio.json lives: iCloud Drive ▸ Folio, or this Mac.
    private(set) var portfolioURL = PortfolioStore.localPortfolioURL
    /// Set when the portfolio exists but couldn't be opened. Nothing is shown or saved
    /// until it's resolved, so an empty portfolio can never overwrite the real one.
    private(set) var storageProblem: String?
    /// Progress while daily price history (for the longer chart ranges) downloads.
    private(set) var historyProgress: (done: Int, total: Int)?
    private(set) var historyError: String?
    /// The free API said "too many requests"; loading pauses and then carries on.
    private(set) var historyRateLimited = false

    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var publishedSnapshot: WidgetSnapshot?
    @ObservationIgnored private var file: PortfolioFile?

    /// This Mac's folder: price cache, widget snapshot, and the portfolio when iCloud is off.
    nonisolated static let directory: URL = {
        #if DEBUG
        if let dir = TestMode.dataDirectory { return dir }
        #endif
        return URL.applicationSupportDirectory.appending(path: "Folio", directoryHint: .isDirectory)
    }()
    nonisolated static let localPortfolioURL = directory.appending(path: "portfolio.json")
    nonisolated static let marketURL = directory.appending(path: "market-cache.json")

    /// iCloud Drive ▸ Folio, if iCloud Drive is on for this Mac.
    nonisolated static var iCloudDirectory: URL? {
        #if DEBUG
        if let root = TestMode.iCloudRoot { return root.appending(path: "Folio", directoryHint: .isDirectory) }
        if TestMode.isActive { return nil }
        #endif
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return root.appending(path: "Folio", directoryHint: .isDirectory)
    }

    var isInICloud: Bool { portfolioURL != Self.localPortfolioURL }

    init() {
        load()
        publishWidgetSnapshot()
        Task { await runRefreshLoop() }
    }

    func valuation(in base: String) -> Valuation {
        Valuation(portfolio: portfolio, market: market, base: base)
    }

    // MARK: - Editing

    func save(_ holding: CryptoHolding) {
        Self.upsert(holding, in: &portfolio.crypto)
        persist()
        if market.coins[holding.coinID] == nil { requestRefresh() }
    }

    func save(_ holding: CashHolding) {
        Self.upsert(holding, in: &portfolio.cash)
        persist()
        if market.usdRates[holding.currency] == nil { requestRefresh() }
    }

    @discardableResult
    func addNFTs(_ collection: NFTCollection, tokens: [Int]) -> Int {
        let owned = Set(portfolio.nfts.filter { $0.collection == collection }.map(\.tokenID))
        let new = Array(Set(tokens).subtracting(owned)).sorted()
        portfolio.nfts += new.map { NFTHolding(collection: collection, tokenID: $0) }
        persist()
        if market.nfts[collection.rawValue] == nil || market.coins["ethereum"] == nil { requestRefresh() }
        return new.count
    }

    func save(_ transaction: AssetTransaction, to ref: HoldingRef) {
        switch ref {
        case .crypto(let id):
            guard let i = portfolio.crypto.firstIndex(where: { $0.id == id }) else { return }
            var holding = portfolio.crypto[i]
            Self.upsert(transaction, in: &holding.transactions)
            portfolio.crypto[i] = holding
        case .cash(let id):
            guard let i = portfolio.cash.firstIndex(where: { $0.id == id }) else { return }
            var holding = portfolio.cash[i]
            Self.upsert(transaction, in: &holding.transactions)
            portfolio.cash[i] = holding
        }
        persist()
    }

    func deleteTransactions(_ ids: Set<UUID>, from ref: HoldingRef) {
        switch ref {
        case .crypto(let id):
            guard let i = portfolio.crypto.firstIndex(where: { $0.id == id }) else { return }
            var holding = portfolio.crypto[i]
            holding.transactions.removeAll { ids.contains($0.id) }
            portfolio.crypto[i] = holding
        case .cash(let id):
            guard let i = portfolio.cash.firstIndex(where: { $0.id == id }) else { return }
            var holding = portfolio.cash[i]
            holding.transactions.removeAll { ids.contains($0.id) }
            portfolio.cash[i] = holding
        }
        persist()
    }

    func holding(_ ref: HoldingRef) -> (any LedgerHolding)? {
        switch ref {
        case .crypto(let id): portfolio.crypto.first { $0.id == id }
        case .cash(let id): portfolio.cash.first { $0.id == id }
        }
    }

    func deleteCrypto(_ ids: Set<UUID>) { portfolio.crypto.removeAll { ids.contains($0.id) }; persist() }
    func deleteCash(_ ids: Set<UUID>) { portfolio.cash.removeAll { ids.contains($0.id) }; persist() }
    func deleteNFTs(_ ids: Set<UUID>) { portfolio.nfts.removeAll { ids.contains($0.id) }; persist() }

    /// Pure on purpose: persisting while `list` (part of `portfolio`) is borrowed inout
    /// would be an exclusivity violation, which traps at runtime.
    private static func upsert<T: Identifiable>(_ item: T, in list: inout [T]) {
        if let i = list.firstIndex(where: { $0.id == item.id }) { list[i] = item } else { list.append(item) }
    }

    // MARK: - Refreshing

    private func requestRefresh() {
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { refreshQueued = true; return }
        isRefreshing = true
        lastAttempt = .now

        let api = MarketAPI(apiKey: Pref.defaults.string(forKey: Pref.apiKey))
        var coinIDs = Set(portfolio.crypto.map(\.coinID))
        if !portfolio.nfts.isEmpty { coinIDs.insert("ethereum") }  // NFT floors are priced in ETH
        coinIDs.insert("bitcoin")                                   // net worth is also shown in BTC
        let collections = Set(portfolio.nfts.map(\.collection)).sorted { $0.rawValue < $1.rawValue }
        var failure: String?

        async let rates = api.exchangeRates()
        async let coins = api.markets(ids: coinIDs.sorted())

        do { market.usdRates = try await rates } catch { failure = "exchange rates (\(error.localizedDescription))" }
        do {
            let fetched = try await coins
            market.coins.merge(fetched) { $1 }
        } catch { failure = failure ?? "prices (\(error.localizedDescription))" }
        for collection in collections {
            do { market.nfts[collection.rawValue] = try await api.nftFloor(collection) }
            catch { failure = failure ?? "NFT floors (\(error.localizedDescription))" }
        }

        if let failure {
            lastError = "Couldn't update \(failure)"
        } else {
            lastError = nil
            market.updated = .now
        }
        write(market, to: Self.marketURL)
        publishWidgetSnapshot()
        isRefreshing = false

        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    // MARK: - Daily price history

    /// Coins whose daily prices the charts need: everything held, plus BTC (net worth in BTC)
    /// and ETH (NFT floors are priced in it).
    var historyCoinIDs: [String] {
        var ids = Set(portfolio.crypto.map(\.coinID))
        ids.insert("bitcoin")
        if !portfolio.nfts.isEmpty { ids.insert("ethereum") }
        return ids.sorted()
    }

    var hasDailyHistory: Bool {
        historyCoinIDs.allSatisfy { !(market.daily[$0] ?? []).isEmpty }
    }

    /// Starts loading daily prices if needed. Runs on its own, so leaving the chart or switching
    /// ranges doesn't cancel a download halfway.
    func requestDailyHistory() {
        Task { await loadDailyHistory() }
    }

    /// Fetches a year of daily prices for any coin not updated in the last day. Requests are spaced
    /// out to stay inside the free API's rate limit; older cached days are kept.
    func loadDailyHistory(spacing: Duration = .seconds(2)) async {
        guard historyProgress == nil else { return }
        let stale = historyCoinIDs.filter { id in
            market.dailyUpdated[id].map { Date.now.timeIntervalSince($0) > 20 * 3600 } ?? true
        }
        guard !stale.isEmpty else { return }
        historyError = nil
        historyProgress = (0, stale.count)
        let key = Pref.defaults.string(forKey: Pref.apiKey) ?? ""
        let api = MarketAPI(apiKey: key)
        // Without a key the free API allows only a few calls a minute, so go slower.
        let gap = key.isEmpty ? max(spacing, .seconds(5)) : spacing
        coins: for (index, id) in stale.enumerated() {
            if index > 0 { try? await Task.sleep(for: gap) }
            for attempt in 1...3 {
                do {
                    let fresh = try await api.dailyHistory(id: id)
                    let firstNew = fresh.first?.date ?? .distantFuture
                    market.daily[id] = (market.daily[id] ?? []).filter { $0.date < firstNew } + fresh
                    market.dailyUpdated[id] = .now
                    historyProgress = (index + 1, stale.count)
                    historyRateLimited = false
                    break
                } catch MarketError.rateLimited where attempt < 3 {
                    historyRateLimited = true
                    try? await Task.sleep(for: .seconds(60))
                } catch {
                    historyError = "Couldn't load price history: \(error.localizedDescription)"
                    break coins
                }
            }
        }
        historyRateLimited = false
        historyProgress = nil
        write(market, to: Self.marketURL)
    }

    private func runRefreshLoop() async {
        while !Task.isCancelled {
            let minutes = Pref.defaults.object(forKey: Pref.refreshMinutes) as? Int ?? 5
            let interval = TimeInterval(max(1, minutes) * 60)
            let wait = lastError == nil ? interval : min(interval, 60)  // retry failures sooner
            if lastAttempt.map({ Date.now.timeIntervalSince($0) >= wait }) ?? true {
                await refresh()
                // Top up the longer chart ranges quietly, well spaced out, after prices are in.
                if lastError == nil {
                    Task {
                        try? await Task.sleep(for: .seconds(20))
                        await loadDailyHistory(spacing: .seconds(6))
                    }
                }
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    // MARK: - Persistence

    func revealDataFile() {
        if FileManager.default.fileExists(atPath: portfolioURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([portfolioURL])
        } else {
            let folder = portfolioURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    private func load() {
        openPortfolio()
        if let data = try? Data(contentsOf: Self.marketURL),
           let cached = try? Self.decoder.decode(MarketData.self, from: data) {
            market = cached
            // Fresh cache covering every holding: skip the launch fetch (kind to free API limits).
            let covered = portfolio.crypto.allSatisfy { cached.coins[$0.coinID] != nil }
                && portfolio.nfts.allSatisfy { cached.nfts[$0.collection.rawValue] != nil }
            if covered { lastAttempt = cached.updated }
        }
    }

    func retryOpeningPortfolio() {
        openPortfolio()
        publishWidgetSnapshot()
        requestRefresh()
    }

    /// Finds and loads portfolio.json, moving it into iCloud Drive the first time that's possible.
    private func openPortfolio() {
        storageProblem = nil
        let wantsICloud = Pref.defaults.object(forKey: Pref.storeInICloud) as? Bool ?? true

        if wantsICloud, let folder = Self.iCloudDirectory {
            let cloud = makeFile(folder.appending(path: "portfolio.json"))
            do {
                if let data = try cloud.read() {
                    use(cloud, contents: data)
                } else {
                    // First time with iCloud Drive: bring this Mac's portfolio over.
                    let local = try Self.readLocalPortfolio()
                    if let local { try cloud.write(local) }
                    use(cloud, contents: local)
                }
                setAsideLocalPortfolio()
                Pref.defaults.set(true, forKey: Pref.portfolioInICloud)
                return
            } catch {
                cloud.stop()
                if Pref.defaults.bool(forKey: Pref.portfolioInICloud) {
                    // The real portfolio is in iCloud Drive: don't show or save a stale local copy.
                    file = nil
                    portfolioURL = cloud.url
                    portfolio = Portfolio()
                    storageProblem = "Folio couldn't open your portfolio in iCloud Drive (\(error.localizedDescription)). "
                        + "Nothing was changed. If macOS asked whether Folio may access iCloud Drive, allow it in "
                        + "System Settings ▸ Privacy & Security ▸ Files & Folders, then try again."
                    return
                }
                dataWarning = "Folio couldn't reach iCloud Drive (\(error.localizedDescription)), so your portfolio "
                    + "stays on this Mac for now. It will move to iCloud Drive once Folio can access it."
            }
        }

        let local = makeFile(Self.localPortfolioURL)
        do {
            use(local, contents: try local.read())
        } catch {
            local.stop()
            file = nil
            portfolioURL = local.url
            portfolio = Portfolio()
            storageProblem = "Folio couldn't open your portfolio (\(error.localizedDescription)). Nothing was changed."
        }
    }

    /// Moves the portfolio between iCloud Drive and this Mac. What's on screen is what moves;
    /// a file already at the destination is kept as a backup rather than overwritten.
    func setICloudStorage(_ enabled: Bool) {
        guard storageProblem == nil, enabled != isInICloud else { return }
        let url: URL
        if enabled {
            guard let folder = Self.iCloudDirectory else { return }
            url = folder.appending(path: "portfolio.json")
        } else {
            url = Self.localPortfolioURL
        }
        let destination = makeFile(url)
        do {
            if destination.exists { try destination.setAside(as: Self.backupName("portfolio-replaced")) }
            try destination.write(Self.encoder.encode(portfolio))
        } catch {
            destination.stop()
            dataWarning = "Couldn't move your portfolio: \(error.localizedDescription)"
            return
        }
        file?.stop()
        file = destination
        portfolioURL = url
        if enabled { setAsideLocalPortfolio() }
        Pref.defaults.set(enabled, forKey: Pref.storeInICloud)
        Pref.defaults.set(enabled, forKey: Pref.portfolioInICloud)
    }

    private func makeFile(_ url: URL) -> PortfolioFile {
        PortfolioFile(url: url) { [weak self] in
            Task { @MainActor in self?.reloadAfterOutsideChange() }
        }
    }

    private func use(_ file: PortfolioFile, contents data: Data?) {
        if self.file !== file { self.file?.stop() }
        self.file = file
        portfolioURL = file.url
        guard let data else { portfolio = Portfolio(); return }
        do {
            portfolio = try Self.decoder.decode(Portfolio.self, from: data)
        } catch {
            // Never overwrite a file we couldn't read — set it aside first.
            let name = Self.backupName("portfolio-unreadable")
            try? file.setAside(as: name)
            portfolio = Portfolio()
            dataWarning = "Folio couldn't read your saved portfolio, so it started empty. The original file was kept as “\(name)” next to your data."
        }
    }

    /// Another device changed the file in iCloud Drive: show its version.
    private func reloadAfterOutsideChange() {
        guard storageProblem == nil, let file, let data = try? file.read(),
              let fresh = try? Self.decoder.decode(Portfolio.self, from: data), fresh != portfolio else { return }
        portfolio = fresh
        publishWidgetSnapshot()
        requestRefresh()
    }

    private static func readLocalPortfolio() throws -> Data? {
        guard FileManager.default.fileExists(atPath: localPortfolioURL.path) else { return nil }
        return try Data(contentsOf: localPortfolioURL)
    }

    /// Once the portfolio lives in iCloud Drive, the copy on this Mac is kept only as a backup.
    private func setAsideLocalPortfolio() {
        guard FileManager.default.fileExists(atPath: Self.localPortfolioURL.path) else { return }
        try? FileManager.default.moveItem(at: Self.localPortfolioURL,
                                          to: Self.directory.appending(path: Self.backupName("portfolio-before-icloud")))
    }

    private static func backupName(_ prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(prefix)-\(formatter.string(from: .now)).json"
    }

    private func persist() {
        guard storageProblem == nil, let file else { return }
        do {
            try file.write(Self.encoder.encode(portfolio))
        } catch {
            dataWarning = "Couldn't save your portfolio: \(error.localizedDescription)"
        }
        publishWidgetSnapshot()
    }

    // MARK: - Widget

    /// Writes the numbers the widget shows and asks WidgetKit to redraw, only when they changed.
    func publishWidgetSnapshot() {
        #if DEBUG
        if TestMode.isActive { return }
        #endif
        let base = Pref.defaults.string(forKey: Pref.baseCurrency) ?? Pref.defaultCurrency
        let valuation = valuation(in: base)
        let history = valuation.history(.week).map(\.value)
        let step = max(1, history.count / 56)  // ~every 3 hours is plenty for a small chart
        let sampled = history.count > 1
            ? stride(from: history.count - 1, through: 0, by: -step).reversed().map { history[$0] }
            : []

        let snapshot = WidgetSnapshot(
            currency: base,
            total: valuation.total,
            change24h: valuation.change24h,
            change24hPercent: valuation.change24hPercent,
            slices: AssetCategory.allCases.map { .init(category: $0.rawValue, value: valuation.total($0)) },
            history: sampled,
            hidden: Pref.defaults.bool(forKey: Pref.hideBalances),
            updated: market.updated ?? .now
        )
        guard snapshot != publishedSnapshot else { return }
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try snapshot.write(to: Self.directory)
            publishedSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "Couldn't update widget: \(error.localizedDescription)"
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
