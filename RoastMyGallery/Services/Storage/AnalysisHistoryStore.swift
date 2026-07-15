import Foundation
import Observation

/// Local persistence for completed analyses.
///
/// Storage choice: Codable + FileManager (one JSON file in Application
/// Support) instead of SwiftData — the models are already Codable JSON
/// payloads, volume is a few KB per record, and this avoids schema/migration
/// machinery. Swap the load/persist internals if that ever changes.
///
/// ALL records are stored regardless of tier; the free-tier "only the most
/// recent is viewable" rule is enforced in the UI via
/// `PurchaseManager.Entitlements`, so upgrading to Pro retroactively unlocks
/// old analyses.
@MainActor
@Observable
final class AnalysisHistoryStore {
    /// Newest first.
    private(set) var records: [AnalysisRecord] = []

    var latest: AnalysisRecord? { records.first }

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
