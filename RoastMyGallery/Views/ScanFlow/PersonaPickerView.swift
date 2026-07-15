import SwiftUI

/// Two equal, neutral persona cards. No default selection, no premium
/// badges — the choice is purely about tone.
struct PersonaPickerView: View {
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(PurchaseManager.self) private var purchaseManager

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            VStack(spacing: Theme.Spacing.s) {
                Text("Pick a voice")
                    .font(Theme.Typography.display)
                Text("How should we talk about your photos?")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.m) {
                ForEach(Persona.allCases) { persona in
                    PersonaCard(
                        persona: persona,
                        isSelected: scanViewModel.selectedPersona == persona
                    ) {
                        scanViewModel.selectedPersona = persona
                    }
                }
            }
            .padding(.top, Theme.Spacing.m)

            Spacer()

            Button("Analyze My Photos") {
                scanViewModel.startScan(entitlements: purchaseManager.entitlements)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(scanViewModel.selectedPersona == nil)

            Text(scanViewModel.selectedPersona == nil
                 ? "Choose a voice to begin"
                 : "Analysis happens on your device")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.l)
        .animation(Theme.motion, value: scanViewModel.selectedPersona)
    }
}

private struct PersonaCard: View {
    let persona: Persona
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: Theme.Spacing.s) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.persona(persona))
                        .frame(width: 56, height: 56)
                    Image(systemName: persona.symbolName)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.top, Theme.Spacing.s)

                Text(persona.displayName)
                    .font(Theme.Typography.headline)
                Text(persona.tagline)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(persona.pickerDescription)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
            .padding(Theme.Spacing.m)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(isSelected ? Theme.Colors.accent : .clear, lineWidth: 2)
            )
            .softShadow()
        }
        .buttonStyle(.plain)
    }
}
