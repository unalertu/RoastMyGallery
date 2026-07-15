import Foundation

/// How far back in the photo library the analysis reaches.
/// Free tier is limited to the last three months; full history is Pro.
enum AnalysisScope: String, Codable, Sendable {
    case lastThreeMonths
    case fullHistory

    /// The earliest creation date to include, or `nil` for no lower bound.
    var startDate: Date? {
        switch self {
        case .lastThreeMonths:
            return Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .fullHistory:
            return nil
        }
    }

    var requiresPro: Bool { self == .fullHistory }
}
