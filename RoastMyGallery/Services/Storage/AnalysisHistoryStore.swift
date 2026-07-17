import Foundation
import Observation

/// Local persistence for completed analyses.
///
/// Storage choice: Codable + FileManager (one JSON file in Application
/// Support) instead of SwiftData — the models are already Codable JSON
/// payloads, volume is a few KB per record, and this avoids schema/migration
/// machinery. Swap the load/persist internals if that ever changes.
///
/// ALL records are viewable — in the gem model the user already spent a
/// gem to generate each one, so history has nothing to gate.
@MainActor
@Observable
final class AnalysisHistoryStore {
    /// Newest first.
    private(set) var records: [AnalysisRecord] = []

    var latest: AnalysisRecord? { records.first }

    /// Stats from the newest record that actually scanned the library.
    /// Standalone hand-picked (Deep Vision) runs carry all-zero placeholder
    /// stats that were never computed OR sent anywhere, so they're skipped.
    /// This is the one rule every stats surface shares — Home's teaser and
    /// snapshot, Gallery Stats, and Data Transparency — so they can't disagree
    /// about what the "latest" scan is.
    var latestScanStats: PhotoStats? {
        records.first(where: { $0.stats.analyzedPhotos > 0 })?.stats
    }

    private let fileURL: URL

    init(fileURL: URL = AnalysisHistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func add(_ record: AnalysisRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func deleteAll() {
        records = []
        persist()
    }

    // MARK: - Disk

    nonisolated static var defaultFileURL: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "RoastMyGallery")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder.backend.decode([AnalysisRecord].self, from: data)
                // Old records can hold since-renamed category labels ("adult")
                // that would still surface in stats, teasers, and share cards.
                .map { $0.modernizingCategories() }
        } catch {
            // Corrupt/incompatible history is not worth crashing over; start
            // fresh. TODO: route through a proper logger.
            records = []
        }
    }

    /// Synchronous atomic write — the payload is a few KB, not worth a queue.
    private func persist() {
        do {
            let data = try JSONEncoder.backend.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // TODO: route through a proper logger.
        }
    }
}
