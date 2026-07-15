import SwiftUI

/// Stage 4: renders the "wrapped"-style card into a UIImage sized for
/// Instagram/TikTok stories (1080×1920 @3x logical 360×640).
@MainActor
struct ShareCardRenderer: ShareCardRendering {
    func renderCard(insight: Insight, stats: PhotoStats) throws -> UIImage {
        let card = ShareCardView(insight: insight, stats: stats)
            .frame(width: 360, height: 640)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3 // 1080×1920 output

        guard let image = renderer.uiImage else {
            throw RenderError.renderFailed
        }
        return image
    }

    enum RenderError: LocalizedError {
        case renderFailed
        var errorDescription: String? { "Couldn't render the share card." }
    }
}
