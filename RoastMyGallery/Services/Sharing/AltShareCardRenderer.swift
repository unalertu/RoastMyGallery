import SwiftUI

/// Renders the editorial share card (`AltShareCardView`) at 1080×1920.
/// Deliberately separate from `ShareCardRenderer` — the classic card and its
/// renderer are untouched; users pick between the two at share time.
@MainActor
struct AltShareCardRenderer: ShareCardRendering {
    /// Force a specific background variant (used by debug rendering);
    /// `nil` = stable per-insight seeded pick.
    var variant: AltCardVariant?

    func renderCard(insight: Insight, stats: PhotoStats) throws -> UIImage {
        let card = AltShareCardView(insight: insight, stats: stats, variant: variant)
            .frame(width: 360, height: 640)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3 // 1080×1920 output

        guard let image = renderer.uiImage else {
            throw ShareCardRenderer.RenderError.renderFailed
        }
        return image
    }
}
