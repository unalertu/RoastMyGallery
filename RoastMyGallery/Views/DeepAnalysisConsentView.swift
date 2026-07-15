import SwiftUI
import PhotosUI

/// Screen 6 — Pro-tier flow: user hand-picks up to 30 photos, sees an
/// explicit, plainly-worded consent notice that THESE photos will be
/// uploaded, and confirms per batch. Calm, no dark patterns: consent is an
/// unchecked opt-in every time, and the primary button stays disabled
/// until it's given.
///
/// This is the only place in the app that can trigger an image upload.
struct DeepAnalysisConsentView: View {
    /// The voice used for commentary — inherited from the analysis this
    /// screen was opened from.
    let persona: Persona

    @Environment(\.dismiss) private var dismiss

    @State private var selection: [PhotosPickerItem] = []
    @State private var hasConsented = false
    @State private var isSubmitting = false
    @State private var commentaries: [PhotoCommentary] = []
    @State private var errorMessage: String?

    private let maxPhotos = 30

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                Group {
                    if commentaries.isEmpty {
                        pickerAndConsent
                    } else {
                        resultsList
                    }
                }
                .transition(.opacity)
            }
            .animation(Theme.motion, value: commentaries.isEmpty)
            .navigationTitle("Deep Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var pickerAndConsent: some View {
        VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.s) {
                Text("A closer look")
                    .font(Theme.Typography.title)
                Text("Pick up to \(maxPhotos) photos for individual, photo-by-photo commentary.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Theme.Typography.bodyLineSpacing)
            }
            .padding(.top, Theme.Spacing.l)

            PhotosPicker(
                selection: $selection,
                maxSelectionCount: maxPhotos,
                matching: .images
            ) {
                Label(
                    selection.isEmpty ? "Choose Photos" : "\(selection.count) photos selected",
                    systemImage: "photo.badge.plus"
                )
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            }

            // Explicit, per-batch consent — required before any upload.
            Toggle(isOn: $hasConsented) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Send these photos for analysis")
                        .font(Theme.Typography.headline)
                    Text("The \(selection.count) photos you picked — and only those — will be uploaded and read by an AI service. Nothing else ever leaves your device.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(2)
                }
            }
            .tint(Theme.Colors.accent)
            .themedCard()
            .disabled(selection.isEmpty)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .tint(Theme.Colors.background)
                } else {
                    Text("Analyze These Photos")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selection.isEmpty || !hasConsented || isSubmitting)
        }
        .padding(Theme.Spacing.l)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(Array(commentaries.enumerated()), id: \.element.id) { index, commentary in
                    // TODO: show the photo thumbnail next to its commentary
                    // (resolve commentary.assetID via PHAsset when picker items carry IDs).
                    Text(commentary.comment)
                        .font(Theme.Typography.body)
                        .lineSpacing(Theme.Typography.bodyLineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.m)
                        .background(
                            Theme.Colors.cardCycle[index % Theme.Colors.cardCycle.count].opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
                        )
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            var photos: [(assetID: String, jpegData: Data)] = []
            for item in selection {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                // PhotosPickerItem.itemIdentifier is only set with a full-library
                // authorization; fall back to a local UUID for mapping.
                photos.append((assetID: item.itemIdentifier ?? UUID().uuidString, jpegData: data))
            }
            // TODO: downscale/re-encode to JPEG before upload to cap payload size.
            commentaries = try await deepVisionService.analyze(
                photos: photos,
                persona: persona
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // TODO: inject via AppEnvironment instead of constructing here once this
    // view is wired into the main flow properly.
    private var deepVisionService: DeepVisionAnalyzing { MockDeepVisionService() }
}
