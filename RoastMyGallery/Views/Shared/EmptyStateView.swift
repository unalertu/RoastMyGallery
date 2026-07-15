import SwiftUI

/// Friendly empty state: layered pastel circles around an SF Symbol, a soft
/// title and one line of copy. Used by Home and History for first-time users.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentSoft)
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 88, height: 88)
                    .softShadow()
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(.bottom, Theme.Spacing.s)

            Text(title)
                .font(Theme.Typography.title)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
        }
        .multilineTextAlignment(.center)
        .padding(Theme.Spacing.l)
    }
}
