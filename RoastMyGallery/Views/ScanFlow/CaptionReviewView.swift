import SwiftUI
import UIKit

/// Deep analysis only: the last gate before any photo leaves the device.
///
/// WHY THIS SCREEN EXISTS: the app — not the user — decides which photos
/// illustrate the story, and it can only decide that *after* the story is
/// written. A consent toggle collected before the scan therefore asks the user
/// to approve a set that neither they nor the app could name yet. This screen
/// makes the consent real and specific: the user sees the exact batch, drops
/// anything they'd rather not send, and only then does anything upload.
///
/// Everything starts selected, because these are the photos their results will
/// show anyway. Removing one only excludes it from the upload — the card still
/// renders, it just gets no caption.
struct CaptionReviewView: View {
    /// Asset IDs of the photos that would be uploaded, in results order.
    let assetIDs: [String]

    @Environment(ScanViewModel.self) private var scanViewModel

    @State private var excluded: Set<String> = []

    private var approved: [String] { assetIDs.filter { !excluded.contains($0) } }

    private static let columns = [GridItem(.adaptive(minimum: 92), spacing: Theme.Spacing.s)]

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            header

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Theme.Spacing.s) {
                    ForEach(assetIDs, id: \.self) { assetID in
                        tile(assetID)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .padding(Theme.Spacing.l)
        .animation(Theme.motion, value: excluded)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Send these photos?")
                .font(Theme.Typography.display)

            Text(explainer)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(3)
        }
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Spacing.m)
    }

    private var explainer: String {
        let subject = assetIDs.count == 1
            ? "This photo is the one"
            : "These \(assetIDs.count) photos are the ones"
        return "Your story is already written. \(subject) your results will show — tap any you'd rather not send. The ones left selected are resized on your device and sent once to our AI provider, Google Gemini, to be captioned. They are not used to train any AI model, and we don't keep a copy."
    }

    // MARK: - Tiles

    private func tile(_ assetID: String) -> some View {
        let isIncluded = !excluded.contains(assetID)
        return Button {
            Haptics.selection()
            if isIncluded {
                excluded.insert(assetID)
            } else {
                excluded.remove(assetID)
            }
        } label: {
            CaptionReviewThumbnail(assetID: assetID)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .stroke(isIncluded ? Theme.Colors.accent : .clear, lineWidth: 2)
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isIncluded ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        // Opaque disc so the symbol reads on any photo.
                        .background(Circle().fill(Theme.Colors.background).padding(3))
                        .padding(Theme.Spacing.xs)
                }
                // Excluded tiles stay visible (so the user can put one back)
                // but clearly read as "not going".
                .opacity(isIncluded ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isIncluded ? "Photo included — tap to exclude" : "Photo excluded — tap to include")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button(sendLabel) {
                Haptics.primary()
                scanViewModel.approveCaptionPhotos(approved)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(approved.isEmpty)

            Button("Continue without captions") {
                Haptics.tap()
                scanViewModel.skipCaptionPhotos()
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            Text(approved.isEmpty
                 ? "Nothing selected — continue without captions."
                 : "Nothing leaves your device until you tap Send.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var sendLabel: String {
        approved.count == 1 ? "Send 1 Photo" : "Send \(approved.count) Photos"
    }
}

/// One square thumbnail, loaded through the same resolver the results cards
/// use (`SegmentThumbnailLoader`) so this screen shows exactly the image the
/// user will see next to their story.
private struct CaptionReviewThumbnail: View {
    let assetID: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.Colors.cream)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task {
            image = await SegmentThumbnailLoader.thumbnail(for: [assetID], side: 240)
        }
    }
}
