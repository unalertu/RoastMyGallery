import SwiftUI

/// Screen 3: calm progress. A soft ring fills during the on-device scan
/// (determinate) and drifts during the LLM call (indeterminate) — no spinners.
struct ScanProgressView: View {
    @Environment(ScanViewModel.self) private var scanViewModel

    private var isDeep: Bool { scanViewModel.selectedDepth == .deep }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            switch scanViewModel.phase {
            case .scanning(let progress):
                ProgressRing(fraction: progress.fraction)

                VStack(spacing: Theme.Spacing.s) {
                    Text("Looking through your photos")
                        .font(Theme.Typography.title)
                    Text(progress.total > 0
                         ? "\(progress.completed) of \(progress.total)"
                         : "Getting ready…")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Theme.motion, value: progress.completed)
                }

                Text(isDeep
                     ? "Scanning on your phone. Before any photo is sent for captions, you'll see exactly which ones and decide."
                     : "Everything stays on your device.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)

            case .generatingInsight:
                DriftingRing()

                VStack(spacing: Theme.Spacing.s) {
                    Text(isDeep ? "Writing your long story" : "Writing your story")
                        .font(Theme.Typography.title)
                    if let persona = scanViewModel.selectedPersona {
                        Text("In your \(persona.displayName.lowercased()) voice…")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                // Deep writes a much longer story on a stronger model; standard
                // is a few seconds. Set the right expectation for each.
                Text(isDeep
                     ? "A deep read takes a little longer — hang tight."
                     : "This usually takes a few seconds.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)

            case .captioning:
                DriftingRing()

                VStack(spacing: Theme.Spacing.s) {
                    Text("Captioning your photos")
                        .font(Theme.Typography.title)
                    // Only the batch approved on `CaptionReviewView` is in
                    // flight — "each photo" read as the whole date range.
                    Text("Adding a note to the photos you approved…")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text("Almost done — this is the last step.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

            default:
                DriftingRing()
            }

            Spacer()

            VStack(spacing: Theme.Spacing.s) {
                // Same as the toolbar's minimize: the run keeps working and
                // the status banner (plus a completion notification if the
                // app is backgrounded) picks it up from here.
                Button("Continue in Background") {
                    Haptics.tap()
                    scanViewModel.minimizeFlow()
                }
                .buttonStyle(SoftButtonStyle())
                // Cancel is only offered during the on-device scan, which is
                // free to abandon. Once generation starts the request is
                // already with the backend — which charges on success whether
                // or not we're still listening — so cancelling could only
                // discard a story that's being paid for.
                if case .scanning = scanViewModel.phase {
                    Button("Cancel") {
                        Haptics.tap()
                        scanViewModel.cancelScan()
                    }
                    .buttonStyle(QuietButtonStyle())
                } else {
                    Text("Your story is already being written and can't be cancelled — feel free to keep browsing.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

/// Determinate soft ring with a percentage in the center.
/// Shared with the Deep Vision flow (photo preparation progress).
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.accentSoft, lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.motion, value: fraction)
            Text("\(Int(fraction * 100))%")
                .font(Theme.Typography.title)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Theme.motion, value: Int(fraction * 100))
        }
        .frame(width: 140, height: 140)
    }
}

/// Indeterminate variant: a short arc drifting slowly around the ring.
/// Shared with the Deep Vision flow (upload + vision-model wait).
struct DriftingRing: View {
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.accentSoft, lineWidth: 10)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 140, height: 140)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
