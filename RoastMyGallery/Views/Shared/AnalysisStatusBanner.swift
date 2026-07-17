import SwiftUI

/// Floating "mini player" chips shown above the tab bar while an analysis
/// runs minimized — and, after a minimized run finishes or fails, until the
/// user acts on it. Covers both long-running flows: the scan pipeline
/// (`ScanViewModel`) and the hand-picked Deep Vision batch
/// (`DeepVisionRunner`); when both are live, their chips stack. Tapping a
/// chip reopens its flow at whatever the run is doing; finished and failed
/// chips also offer a small ✕ to dismiss in place.
struct AnalysisStatusBanner: View {
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(DeepVisionRunner.self) private var deepVisionRunner

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let state = scanState {
                chip(
                    for: state,
                    open: openScan,
                    dismissNotice: { scanViewModel.dismissBackgroundNotice() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let state = deepVisionState {
                chip(
                    for: state,
                    open: openDeepVision,
                    dismissNotice: { deepVisionRunner.dismissBackgroundNotice() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.motion, value: [scanState, deepVisionState])
    }

    // MARK: - State

    private enum ChipState: Equatable {
        case running(label: String, fraction: Double?)
        case ready(title: String, headline: String)
        case failed(title: String)
    }

    private var scanState: ChipState? {
        guard !scanViewModel.isFlowPresented else { return nil }
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
                return .ready(title: "Your analysis is ready", headline: record.insight.headline)
            }
            if scanViewModel.backgroundFailureMessage != nil {
                return .failed(title: "Analysis didn't finish")
            }
            return nil
        }
    }

    private var deepVisionState: ChipState? {
        guard !deepVisionRunner.isFlowPresented else { return nil }
        switch deepVisionRunner.phase {
        case .preparing(let done, let total):
            return .running(
                label: "Preparing your photos",
                fraction: total > 0 ? Double(done) / Double(total) : nil
            )
        case .analyzing:
            return .running(label: "Reading your photos", fraction: nil)
        default:
            if let record = deepVisionRunner.backgroundCompletion {
                return .ready(title: "Deep Vision is ready", headline: record.insight.headline)
            }
            if deepVisionRunner.backgroundFailureMessage != nil {
                return .failed(title: "Deep Vision didn't finish")
            }
            return nil
        }
    }

    private func openScan() {
        if scanViewModel.backgroundCompletion != nil {
            scanViewModel.openBackgroundResult()
        } else if scanViewModel.backgroundFailureMessage != nil {
            scanViewModel.reopenFailedRun()
        } else {
            scanViewModel.presentFlow()
        }
    }

    private func openDeepVision() {
        if deepVisionRunner.backgroundCompletion != nil {
            deepVisionRunner.openBackgroundResult()
        } else if deepVisionRunner.backgroundFailureMessage != nil {
            deepVisionRunner.reopenFailedRun()
        } else {
            deepVisionRunner.presentFlow()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func chip(
        for state: ChipState,
        open: @escaping () -> Void,
        dismissNotice: @escaping () -> Void
    ) -> some View {
        switch state {
        case .running(let label, let fraction):
            chipChrome(action: open, dismiss: nil) {
                if let fraction {
                    MiniProgressRing(fraction: fraction)
                } else {
                    MiniDriftingRing()
                }
                titles(label, subtitle: "Tap to watch — or keep browsing")
            }

        case .ready(let title, let headline):
            chipChrome(action: open, dismiss: dismissNotice) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                titles(title, subtitle: headline)
            }

        case .failed(let title):
            chipChrome(action: open, dismiss: dismissNotice) {
                Image(systemName: "cloud.drizzle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Colors.danger)
                titles(title, subtitle: "Tap to try again")
            }
        }
    }

    /// Shared chip chrome: surface card, one soft shadow. The main area is
    /// one big button; the ✕ (when present) is a SIBLING of that button, not
    /// nested inside it — nested SwiftUI buttons hit-test unreliably.
    private func chipChrome(
        action: @escaping () -> Void,
        dismiss: (() -> Void)?,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Button(action: action) {
                HStack(spacing: Theme.Spacing.m) {
                    content()
                    Spacer(minLength: dismiss == nil ? Theme.Spacing.s : 0)
                    if dismiss == nil {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let dismiss {
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.s) // comfortable hit target inside the chip
                }
                .buttonStyle(.plain)
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
