import Foundation

/// portfolio.json on disk. Reads and writes go through NSFileCoordinator so they cooperate
/// with iCloud Drive syncing, and `onChange` fires when another device changes the file.
final class PortfolioFile: NSObject, NSFilePresenter, @unchecked Sendable {
    let url: URL
    private let onChange: @Sendable () -> Void

    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var presentedItemURL: URL? { url }

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        onChange()
    }

    /// The file's contents, or nil if there's no file yet. Throws when a file exists but
    /// can't be read (no permission, or iCloud couldn't download it).
    func read() throws -> Data? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<Data?, any Error> = .success(nil)
        NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result {
                FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// Renames the file to `name` in the same folder, keeping it as a backup.
    func setAside(as name: String) throws {
        let destination = url.deletingLastPathComponent().appending(path: name)
        var coordinationError: NSError?
        var moveError: (any Error)?
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: url, options: .forMoving,
                                                          writingItemAt: destination, options: .forReplacing,
                                                          error: &coordinationError) { from, to in
            do { try FileManager.default.moveItem(at: from, to: to) } catch { moveError = error }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}
