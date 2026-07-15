import SwiftUI

/// A visually rich stats dashboard showing the user's gallery statistics
/// from their latest analysis — selfies, animals, categories, and more —
/// presented as colourful, card-based tiles in a grid layout.
struct GalleryStatsView: View {
    @Environment(AnalysisHistoryStore.self) private var history

    /// Two-column grid for the stat cards.
    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.m),
        GridItem(.flexible(), spacing: Theme.Spacing.m)
    ]

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                if let stats = history.latest?.stats {
                    statsContent(stats)
                } else {
                    emptyState
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .navigationTitle("Gallery Stats")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
    }

    // MARK: - Stats Content

    private func statsContent(_ stats: PhotoStats) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            // Hero — total photos
            heroCard(stats)

            // Grid of stat tiles
            LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                // Core counters
                statTile(
                    icon: "person.crop.circle",
                    value: "\(stats.selfieCount)",
                    label: "Selfies",
                    detail: "\(Int((stats.selfieRatio * 100).rounded()))% of photos",
                    color: Theme.Colors.dustyRose
                )
                statTile(
                    icon: "rectangle.on.rectangle",
                    value: "\(stats.screenshotCount)",
                    label: "Screenshots",
                    detail: nil,
                    color: Theme.Colors.powderBlue
                )
                statTile(
                    icon: "star.fill",
                    value: "\(stats.favoriteCount)",
                    label: "Favorites",
                    detail: nil,
                    color: Theme.Colors.sage
                )

                // Busiest hour
                if let busiest = busiestHourTile(stats.photosByHourOfDay) {
                    statTile(
                        icon: "clock.fill",
                        value: busiest.value,
                        label: "Busiest Hour",
                        detail: busiest.detail,
                        color: Theme.Colors.cream
                    )
                }

                // Animals
                ForEach(
                    stats.animalCounts.sorted(by: { $0.value > $1.value }),
                    id: \.key
                ) { animal, count in
                    statTile(
                        icon: animalIcon(animal),
                        value: "\(count)",
                        label: animal.capitalized,
                        detail: nil,
                        color: Theme.Colors.cardCycle[
                            abs(animal.hashValue) % Theme.Colors.cardCycle.count
                        ]
                    )
                }
            }

            // Top categories section
            if !stats.topCategories.isEmpty {
                categoriesSection(stats.topCategories)
            }

            // Face distribution
            if !stats.faceCountBuckets.isEmpty {
                facesSection(stats.faceCountBuckets)
            }

            // Location clusters
            if !stats.topLocationClusters.isEmpty {
                locationSection(stats.topLocationClusters)
            }

            // Timestamp footer
            Text("Based on analysis from \(stats.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .padding(Theme.Spacing.l)
    }

    // MARK: - Hero Card

    private func heroCard(_ stats: PhotoStats) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Colors.accent)

            Text("\(stats.analyzedPhotos)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Photos Analyzed")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("out of \(stats.totalPhotos) total")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .background(
            LinearGradient(
                colors: [Theme.Colors.accentSoft.opacity(0.5), Theme.Colors.surface],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .softShadow()
    }

    // MARK: - Stat Tile

    private func statTile(
        icon: String,
        value: String,
        label: String,
        detail: String?,
        color: Color
    ) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Colors.accent)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(label)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.l)
        .padding(.horizontal, Theme.Spacing.s)
        .background(color.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .softShadow()
    }

    // MARK: - Categories Section

    private func categoriesSection(_ categories: [CategoryCount]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            sectionHeader(icon: "tag.fill", title: "Top Categories")

            VStack(spacing: Theme.Spacing.s) {
                ForEach(Array(categories.prefix(6).enumerated()), id: \.element.category) { index, cat in
                    HStack(spacing: Theme.Spacing.m) {
                        // Rank badge
                        Text("\(index + 1)")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Colors.surface)
                            .frame(width: 24, height: 24)
                            .background(Theme.Colors.accent, in: Circle())

                        Text(cat.category.capitalized)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Text("\(cat.count)")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Colors.accent)

                        Text(cat.count == 1 ? "photo" : "photos")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    if index < min(categories.count, 6) - 1 {
                        Divider().overlay(Theme.Colors.background)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    // MARK: - Faces Section

    private func facesSection(_ buckets: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            sectionHeader(icon: "person.2.fill", title: "Faces in Photos")

            let order = ["0 faces", "1 face", "2+ faces"]
            let ordered = buckets
                .sorted { lhs, rhs in
                    (order.firstIndex(of: lhs.key) ?? .max) < (order.firstIndex(of: rhs.key) ?? .max)
                }

            HStack(spacing: Theme.Spacing.m) {
                ForEach(ordered, id: \.key) { key, count in
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("\(count)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(key)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.m)
                    .background(
                        Theme.Colors.powderBlue.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    // MARK: - Location Section

    private func locationSection(_ clusters: [LocationClusterStat]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            sectionHeader(icon: "location.fill", title: "Location Clusters")

            HStack(spacing: Theme.Spacing.m) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("\(clusters.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Clusters")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)

                if let topShare = clusters.map(\.share).max() {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("\(Int((topShare * 100).rounded()))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Top cluster")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .padding(.horizontal, Theme.Spacing.m)
            .background(
                Theme.Colors.sage.opacity(0.25),
                in: RoundedRectangle(cornerRadius: Theme.Radius.small)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func animalIcon(_ animal: String) -> String {
        let lowered = animal.lowercased()
        if lowered.contains("cat") { return "cat.fill" }
        if lowered.contains("dog") { return "dog.fill" }
        if lowered.contains("bird") { return "bird.fill" }
        if lowered.contains("fish") { return "fish.fill" }
        if lowered.contains("rabbit") || lowered.contains("bunny") { return "rabbit.fill" }
        if lowered.contains("tortoise") || lowered.contains("turtle") { return "tortoise.fill" }
        if lowered.contains("lizard") { return "lizard.fill" }
        return "pawprint.fill"
    }

    private func busiestHourTile(_ hours: [Int]) -> (value: String, detail: String)? {
        guard let maxCount = hours.max(), maxCount > 0,
              let hour = hours.firstIndex(of: maxCount) else { return nil }
        var components = DateComponents()
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else { return nil }
        let time = date.formatted(.dateTime.hour())
        return (value: time, detail: "\(maxCount) photos")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(Theme.Colors.accent.opacity(0.6))

            VStack(spacing: Theme.Spacing.s) {
                Text("No stats yet")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Run your first gallery analysis and your\nstatistics will appear right here.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Theme.Typography.bodyLineSpacing)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
    }
}
