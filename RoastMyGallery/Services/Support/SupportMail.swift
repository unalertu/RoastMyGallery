import Foundation
import UIKit

/// Every outbound support message the app composes — general feedback and
/// content reports — built in one place so they share an address, a subject
/// convention, and the same device/version footer.
///
/// WHY MAIL AND NOT A BACKEND ENDPOINT: the analysis being reported exists only
/// on the device. The backend never stores a generated story (see the privacy
/// contract in `PhotoStats` / `legal/privacy-policy.md`), so there is nothing
/// server-side for a report to point at — the report has to carry the text with
/// it. A mail draft also means the user reads and edits exactly what leaves
/// their phone, which a silent POST would not.
enum SupportMail {
    /// Published contact address, also listed in the Privacy Policy and Terms.
    static let address = "roastmygallery@gmail.com"

    /// "1.0 (1)" — shown in Settings → About and attached to every message.
    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Report one AI-written analysis as offensive or otherwise inappropriate.
    ///
    /// App Store Review Guideline 1.2 asks any app that generates content for a
    /// way to report what it produced. The draft quotes the generated text so a
    /// report is actually actionable — a complaint we can't read is a complaint
    /// we can't fix the prompts for (see `backend/lib/prompts.js`).
    static func contentReportURL(for record: AnalysisRecord) -> URL? {
        let generated = record.createdAt.formatted(date: .abbreviated, time: .shortened)
        return url(
            subject: "Roast My Gallery — report content",
            body: """


            —
            Please tell us what was wrong with this analysis above this line.
            We read every report and tighten the writing rules that produced it.

            REPORTED CONTENT — \(record.persona.displayName) voice, generated \(generated):

            \(quoted(record))

            \(environmentFooter)
            """
        )
    }

    // MARK: - Pieces

    /// Character budget for the quoted analysis. A `mailto:` URL is handed to
    /// Mail through the URL system, and an over-long one is silently dropped
    /// instead of opening — so a deep run's 12–16 beats get trimmed rather than
    /// pasted whole. The user can always send the rest in a reply.
    private static let quotedContentLimit = 1500

    /// The generated text as the user saw it: headline, the quotable line, then
    /// the narrative beats (or the legacy single body when a record predates
    /// segments). Photo captions are left out on purpose — they describe the
    /// user's own photos, and the story is what a report is about.
    private static func quoted(_ record: AnalysisRecord) -> String {
        var parts = [record.insight.headline]
        if let shareLine = record.insight.shareLine {
            parts.append("“\(shareLine)”")
        }
        if let segments = record.insight.segments, !segments.isEmpty {
            parts.append(contentsOf: segments.map(\.text))
        } else {
            parts.append(record.insight.body)
        }

        let joined = parts.joined(separator: "\n\n")
        guard joined.count > quotedContentLimit else { return joined }
        return String(joined.prefix(quotedContentLimit))
            + "\n\n[trimmed to keep this draft sendable — ask and we'll request the rest]"
    }

    private static var environmentFooter: String {
        """
        App version: \(appVersion)
        Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)
        """
    }

    private static func url(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
