import SwiftUI

/// Floating "mini player" chip shown above the tab bar while an analysis runs
/// minimized — and, after a minimized run finishes or fails, until the user
/// acts on it. Tapping reopens the scan flow at whatever the run is doing;
/// the finished and failed states also offer a small ✕ to dismiss in place.
struct AnalysisStatusBanner: View {
    @Environment(ScanViewModel.self) private var scanViewModel

    var body: some View {
        Group {
            if !scanViewModel.isFlowPresented, let state {
                banner(for: state)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.motion, value: state)
    }

    // MARK: - State

    private enum BannerState: Equatable {
        case running(label: String, fraction: Double?)
        case ready(headline: String)
        case failed
    }

    private var state: BannerState? {
        switch scanViewModel.phase {
        case .scanning(let progress):
            return .running(
                label: "Looking through your photos",
                fraction: progress.total > 0 ? progress.fraction : nil
            )
        case .generatingInsight:
            return .running(label: "Writing your story", fraction: nil)
        case .captioning:
            return .running(label: "Captioning your photos", fraction: nil)
        default:
            if let record = scanViewModel.backgroundCompletion {
                return .ready(headline: record.insight.headline)
            }
            if scanViewModel.backgroundFailureMessage != nil {
                return .failed
            }
            return nil
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func banner(for state: BannerState) -> some View {
        switch state {
        case .running(let label, let fraction):
            chip(action: { scanViewModel.presentFlow() }, dismissable: false) {
                if let fraction {
                    MiniProgressRing(fraction: fraction)
                } else {
                    MiniDriftingRing()
                }
                titles(label, subtitle: "Tap to watch — or keep browsing")
            }

        case .ready(let headline):
            chip(action: { scanViewModel.openBackgroundResult() }, dismissable: true) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                titles("Your analysis is ready", subtitle: headline)
            }

        case .failed:
            chip(action: { scanViewModel.reopenFailedRun() }, dismissable: true) {
                Image(systemName: "cloud.drizzle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Colors.danger)
                titles("Analysis didn't finish", subtitle: "Tap to try again")
            }
        }
    }

    /// Shared chip chrome: surface card, one soft shadow. The main area is
    /// one big button; the ✕ (when present) is a SIBLING of that button, not
    /// nested inside it — nested SwiftUI buttons hit-test unreliably.
    private func chip(
        action: @escaping () -> Void,
        dismissable: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Button(action: action) {
                HStack(spacing: Theme.Spacing.m) {
                    content()
                    Spacer(minLength: dismissable ? 0 : Theme.Spacing.s)
                    if !dismissable {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if dismissable {
                Spacer(minLength: 0)
                dismissButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        .softShadow()
    }

    private func titles(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private var dismissButton: some View {
        Button {
            scanViewModel.dismissBackgroundNotice()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.s) // comfortable hit target inside the chip
        }
        .buttonStyle(.plain)
    }
}

/// 26pt determinate ring — the banner-sized sibling of `ProgressRing`.
private struct MiniProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.accentSoft, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.motion, value: fraction)
        }
        .frame(width: 26, height: 26)
    }
}

/// 26pt indeterminate ring — the banner-sized sibling of `DriftingRing`.
private struct MiniDriftingRing: View {
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.accentSoft, lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 26, height: 26)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
