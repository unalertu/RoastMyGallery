import SwiftUI

/// Celebratory overlay shown after a successful credit purchase.
/// Matches the pastel, rounded DesignSystem aesthetic while adding
/// confetti particles and a satisfying checkmark reveal.
struct PurchaseSuccessView: View {
    let creditsAdded: Int
    let newBalance: Int
    var onDismiss: () -> Void

    // MARK: - Animation state

    @State private var showCheckmark = false
    @State private var showContent = false
    @State private var showConfetti = false
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0
    @State private var displayedCredits = 0
    @State private var showButton = false
    @State private var isDismissing = false

    var body: some View {
        ZStack {
            // Backdrop — cream with a radial glow
            Theme.Colors.background.ignoresSafeArea()

            // Soft radial accent wash behind the ring
            RadialGradient(
                colors: [
                    Theme.Colors.accentSoft.opacity(0.6),
                    Theme.Colors.background.opacity(0)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
            .ignoresSafeArea()

            // Confetti layer
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: Theme.Spacing.l) {
                Spacer()

                // Animated checkmark ring
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(Theme.Colors.accentSoft, lineWidth: 6)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringScale * 1.15)
                        .opacity(ringOpacity * 0.5)

                    // Main ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Theme.Colors.accent, Theme.Colors.dustyRose],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 8
                        )
                        .frame(width: 130, height: 130)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Inner fill
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Checkmark
                    if showCheckmark {
                        Image(systemName: "checkmark")
                            .font(.system(size: 48, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.bottom, Theme.Spacing.m)

                // Text content
                if showContent {
                    VStack(spacing: Theme.Spacing.m) {
                        Text("Purchase Successful!")
                            .font(Theme.Typography.display)
                            .multilineTextAlignment(.center)
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                        // Credit count with counter animation
                        VStack(spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.s) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .symbolEffect(.bounce, value: displayedCredits)

                                Text("+\(displayedCredits)")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .contentTransition(.numericText())
                                    .animation(.easeOut(duration: 0.6), value: displayedCredits)
                            }

                            Text("credits added")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                        // New balance pill
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: 14, weight: .medium))
                            Text("Balance: \(newBalance) credits")
                                .font(Theme.Typography.headline)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.8))
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.m)
                        .background(Theme.Colors.surface, in: Capsule())
                        .softShadow()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                Spacer()

                // Continue button — appears after the celebration plays
                if showButton {
                    Button("Continue") { runExit() }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, Theme.Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .disabled(isDismissing)
                }
            }
            .opacity(isDismissing ? 0 : 1)
            .scaleEffect(isDismissing ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.6), value: isDismissing)
            .padding(Theme.Spacing.l)
        }
        .onAppear { runEntrance() }
    }

    // MARK: - Animation sequence

    private func runEntrance() {
        // Step 1: Ring scales in (0.0s → 0.8s)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) {
            ringScale = 1.0
            ringOpacity = 1.0
        }

        // Step 2: Checkmark pops in (0.6s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.6)) {
            showCheckmark = true
        }

        // Step 3: Confetti burst (0.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation { showConfetti = true }
        }

        // Step 4: Content slides up (1.2s)
        withAnimation(.easeOut(duration: 0.7).delay(1.2)) {
            showContent = true
        }

        // Step 5: Credit counter ticks up (1.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.8)) {
                displayedCredits = creditsAdded
            }
        }

        // Step 6: Continue button fades in (3.0s)
        withAnimation(.easeOut(duration: 0.5).delay(3.0)) {
            showButton = true
        }
    }

    // MARK: - Exit animation

    private func runExit() {
        isDismissing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            onDismiss()
        }
    }
}

// MARK: - Confetti particle system

/// Lightweight confetti using simple shapes with randomised fall animation.
/// Soft pastel colors matching the DesignSystem palette.
private struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPiece(particle: particle, containerSize: geo.size)
                }
            }
            .onAppear {
                particles = (0..<50).map { _ in
                    ConfettiParticle(containerWidth: geo.size.width)
                }
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
    let delay: Double
    let duration: Double
    let shape: ConfettiShape

    enum ConfettiShape: CaseIterable {
        case circle, roundedRect, capsule
    }

    init(containerWidth: CGFloat) {
        x = CGFloat.random(in: 0...containerWidth)
        size = CGFloat.random(in: 5...12)
        rotation = Double.random(in: 0...360)
        delay = Double.random(in: 0...0.5)
        duration = Double.random(in: 1.8...3.0)
        shape = ConfettiShape.allCases.randomElement()!

        let palette: [Color] = [
            Theme.Colors.accent,
            Theme.Colors.dustyRose,
            Theme.Colors.sage,
            Theme.Colors.powderBlue,
            Theme.Colors.accentSoft,
            Theme.Colors.cream
        ]
        color = palette.randomElement()!
    }
}

private struct ConfettiPiece: View {
    let particle: ConfettiParticle
    let containerSize: CGSize

    @State private var y: CGFloat = -20
    @State private var rot: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        confettiShapeView
            .frame(width: particle.size, height: particle.size * (particle.shape == .capsule ? 2.5 : 1))
            .rotationEffect(.degrees(rot))
            .position(x: particle.x, y: y)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeIn(duration: particle.duration)
                    .delay(particle.delay)
                ) {
                    y = containerSize.height + 40
                    rot = particle.rotation + Double.random(in: 180...540)
                }

                // Fade out near the end
                withAnimation(
                    .easeIn(duration: particle.duration * 0.4)
                    .delay(particle.delay + particle.duration * 0.6)
                ) {
                    opacity = 0
                }
            }
    }

    @ViewBuilder
    private var confettiShapeView: some View {
        switch particle.shape {
        case .circle:
            Circle().fill(particle.color)
        case .roundedRect:
            RoundedRectangle(cornerRadius: 2).fill(particle.color)
        case .capsule:
            Capsule().fill(particle.color)
        }
    }
}

// MARK: - Preview

#Preview("Purchase Success") {
    PurchaseSuccessView(
        creditsAdded: 10,
        newBalance: 13,
        onDismiss: {}
    )
}
