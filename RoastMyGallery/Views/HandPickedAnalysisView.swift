import SwiftUI

/// Standalone entry for the Hand-Picked (Deep Vision) flow, reachable from the
/// "New Analysis" options sheet. Unlike the in-results entry (which inherits a
/// persona and stats from an existing analysis), this one has neither, so it
/// asks for a voice first, then hands off to the unchanged consent + pick +
/// upload screen with placeholder stats.
struct HandPickedAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var persona: Persona?

    var body: some View {
        if let persona {
            // The consent screen owns its own chrome (nav bar, close button).
            DeepAnalysisConsentView(persona: persona, sourceStats: .handPickedPlaceholder())
        } else {
            personaPicker
        }
    }

    private var personaPicker: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                VStack(spacing: Theme.Spacing.l) {
                    Spacer()

                    VStack(spacing: Theme.Spacing.s) {
                        Text("Pick a voice")
                            .font(Theme.Typography.display)
                        Text("How should we talk about the photos you choose?")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .multilineTextAlignment(.center)

                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(Persona.allCases) { option in
                            Button {
                                withAnimation(Theme.motion) { persona = option }
                            } label: {
                                VStack(spacing: Theme.Spacing.s) {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.Colors.persona(option))
                                            .frame(width: 56, height: 56)
                                        Image(systemName: option.symbolName)
                                            .font(.system(size: 22, weight: .light))
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                    }
                                    Text(option.displayName)
                                        .font(Theme.Typography.headline)
                                    Text(option.tagline)
                                        .font(Theme.Typography.label)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
                                .padding(Theme.Spacing.m)
                                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                                .softShadow()
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    Text("Next: pick up to 30 photos · \(PurchaseManager.deepVisionCost) credits")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle("Hand-Picked")
            .navigationBarTitleDisplayMode(.inline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }
}
