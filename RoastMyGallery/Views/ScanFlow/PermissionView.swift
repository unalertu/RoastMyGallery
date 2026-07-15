import SwiftUI

/// Screen 1: explains why photo access is needed. The on-device privacy
/// promise is the trust signal, so it gets its own prominent card.
struct PermissionView: View {
    @Environment(ScanViewModel.self) private var scanViewModel

    private var isDenied: Bool { scanViewModel.phase == .permissionDenied }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            // Soft layered icon in pastel circles.
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentSoft)
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 104, height: 104)
                    .softShadow()
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(spacing: Theme.Spacing.s) {
                Text("Let's look at your photos")
                    .font(Theme.Typography.display)
                Text("We find patterns — what you photograph, when, and how many selfies you're hiding.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(Theme.Typography.bodyLineSpacing)
            }
            .multilineTextAlignment(.center)

            // The trust signal, styled prominently.
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Your photos never leave your device")
                        .font(Theme.Typography.headline)
                    Text("All analysis happens on your phone. Only anonymous statistics are used to write your story.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()

            Spacer()

            if isDenied {
                Text("Photo access is currently off. You can enable it in Settings.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Allow Photo Access") {
                    Task { await scanViewModel.requestPermission() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.l)
    }
}
