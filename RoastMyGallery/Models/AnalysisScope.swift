import Foundation

/// How far the analysis reaches into the photo library.
enum AnalysisScope: Sendable, Hashable {
    /// Every photo in the library.
    case fullHistory
    /// Legacy value from before scoped modes existed. No longer reachable
    /// from the UI — kept only so pre-existing persisted records still decode.
    case lastThreeMonths
    /// A specific month or custom date range, inclusive on both ends.
    case dateRange(start: Date, end: Date, label: String)
    /// A single user photo album, identified by its PhotoKit local identifier.
    case album(identifier: String, name: String)

    /// The earliest creation date to include, or `nil` for no lower bound.
    var startDate: Date? {
        switch self {
        case .fullHistory, .album:
            return nil
        case .lastThreeMonths:
            return Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .dateRange(let start, _, _):
            return start
        }
    }

    /// The latest creation date to include, or `nil` for no upper bound.
    var endDate: Date? {
        if case .dateRange(_, let end, _) = self { return end }
        return nil
    }

    /// The album to filter by, when this scope is album-based.
    var albumIdentifier: String? {
        if case .album(let identifier, _) = self { return identifier }
        return nil
    }

    /// Human-readable label, used both in-app and as narrative context sent
    /// to the insight backend (it's part of the `PhotoStats` JSON payload).
    var displayLabel: String {
        switch self {
        case .fullHistory: return "Full history"
        case .lastThreeMonths: return "Last 3 months"
        case .dateRange(_, _, let label): return label
        case .album(_, let name): return name
        }
    }
}

// MARK: - Codable

/// Hand-written so old persisted records (encoded when this was a plain
/// `String` enum: `"fullHistory"` / `"lastThreeMonths"`) keep decoding
/// correctly instead of falling into `AnalysisHistoryStore`'s "corrupt →
/// start fresh" path. New records encode as a small keyed object instead.
extension AnalysisScope: Codable {
    private enum Kind: String, Codable {
        case fullHistory, lastThreeMonths, dateRange, album
    }

    private enum CodingKeys: String, CodingKey {
        case kind, start, end, label, identifier, name
    }

    init(from decoder: Decoder) throws {
        // Legacy shape: a bare string from the old `String`-backed enum.
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            self = (legacy == "lastThreeMonths") ? .lastThreeMonths : .fullHistory
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .fullHistory:
            self = .fullHistory
        case .lastThreeMonths:
            self = .lastThreeMonths
        case .dateRange:
            self = .dateRange(
                start: try container.decode(Date.self, forKey: .start),
                end: try container.decode(Date.self, forKey: .end),
                label: try container.decode(String.self, forKey: .label)
            )
        case .album:
            self = .album(
                identifier: try container.decode(String.self, forKey: .identifier),
                name: try container.decode(String.self, forKey: .name)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fullHistory:
            try container.encode(Kind.fullHistory, forKey: .kind)
        case .lastThreeMonths:
            try container.encode(Kind.lastThreeMonths, forKey: .kind)
        case .dateRange(let start, let end, let label):
            try container.encode(Kind.dateRange, forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(label, forKey: .label)
        case .album(let identifier, let name):
            try container.encode(Kind.album, forKey: .kind)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(name, forKey: .name)
        }
    }
}
