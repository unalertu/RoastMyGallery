import Photos
import SwiftUI
import UIKit

// MARK: - Identifiable wrapper for sheet presentation

/// Wraps a UIImage so it can drive a `.sheet(item:)` binding.
/// Optionally carries an asset ID so the sheet can fetch the full-resolution
/// original from PhotoKit (the card thumbnails are only 400 px).
struct ZoomablePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    /// PHAsset local identifier — when present the sheet loads the original.
    var assetID: String?
}

/// Wraps a `UIScrollView` + `UIImageView` to deliver the exact same
/// pinch-to-zoom, double-tap-to-zoom, and bounce-back behavior that
/// the native Photos app uses.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator(image: image) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        // Pin imageView to scrollView's content layout guide
        let contentGuide = scrollView.contentLayoutGuide
        let frameGuide = scrollView.frameLayoutGuide

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            // Make the image fill the visible area at minimum zoom
            imageView.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: frameGuide.heightAnchor),
        ])

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        // Double-tap to zoom
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Swap in updated (higher-res) image without resetting zoom.
        guard let imageView = context.coordinator.imageView else { return }
        if imageView.image !== image {
            imageView.image = image
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let image: UIImage
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        init(image: UIImage) { self.image = image }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            let offsetX = max(0, (boundsSize.width - contentSize.width) / 2)
            let offsetY = max(0, (boundsSize.height - contentSize.height) / 2)

            imageView.center = CGPoint(
                x: contentSize.width / 2 + offsetX,
                y: contentSize.height / 2 + offsetY
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let zoomRect = zoomRect(for: scrollView, scale: 3.0, center: location)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private func zoomRect(for scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2
            )
            return CGRect(origin: origin, size: size)
        }
    }
}

// MARK: - Sheet content

/// The sheet that wraps the zoomable image. Dark background, close button,
/// presented as a non-full-screen `.sheet`.
///
/// When an `assetID` is available, the sheet immediately shows the low-res
/// thumbnail, then fetches the full-resolution original from PhotoKit and
/// swaps it in seamlessly.
struct PhotoZoomSheet: View {
    let photo: ZoomablePhoto
    @Environment(\.dismiss) private var dismiss

    @State private var displayImage: UIImage

    init(photo: ZoomablePhoto) {
        self.photo = photo
        _displayImage = State(initialValue: photo.image)
    }

    var body: some View {
        ZStack {
            ZoomableImageView(image: displayImage)
                .ignoresSafeArea()

            // Close button — top-trailing
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .padding(Theme.Spacing.m)
                }
                Spacer()
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .task { await loadFullResolution() }
    }

    /// Fetch the full-resolution photo from PHAsset if an ID is available.
    private func loadFullResolution() async {
        guard let assetID = photo.assetID else { return }
        guard let fullImage = await Self.fetchFullImage(assetID: assetID) else { return }
        displayImage = fullImage
    }

    /// Loads the highest-quality version of a PHAsset by its local identifier.
    private static func fetchFullImage(assetID: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = fetched.firstObject else { return nil }

            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none          // full original, no downscale
            options.isNetworkAccessAllowed = true // download from iCloud if needed

            // Request at the photo's full pixel size.
            let targetSize = CGSize(
                width: CGFloat(asset.pixelWidth),
                height: CGFloat(asset.pixelHeight)
            )

            var result: UIImage?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                result = image
            }
            return result
        }.value
    }
}

// MARK: - View Modifier

extension View {
    /// Presents a native-feel photo zoom sheet when the binding holds a photo.
    func photoZoom(photo: Binding<ZoomablePhoto?>) -> some View {
        self.sheet(item: photo) { item in
            PhotoZoomSheet(photo: item)
        }
    }
}
