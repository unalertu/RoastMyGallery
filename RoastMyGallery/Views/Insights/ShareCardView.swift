import SwiftUI

/// The story-sized (9:16) card design rendered by `ShareCardRenderer`.
/// Pure SwiftUI so it can be iterated on with previews.
struct ShareCardView: View {
    let insight: Insight
    let stats: PhotoStats

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("MY GALLERY, ROASTED")
                .font(.caption.bold())
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))

            Text(insight.headline)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                ForEach(insight.superlatives.prefix(4), id: \.self) { superlative in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(superlative.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.6))
                        Text(superlative.detail)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
            }

            Spacer()

            HStack {
                Text("\(stats.analyzedPhotos) photos analyzed")
                Spacer()
                HStack(spacing: 6) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text("Roast My Gallery")
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.55, green: 0.15, blue: 0.85),
                         Color(red: 0.95, green: 0.35, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
