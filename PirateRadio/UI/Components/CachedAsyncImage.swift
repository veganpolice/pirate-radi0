import SwiftUI

/// A cached version of AsyncImage that avoids reloading from network on view re-renders.
struct CachedAsyncImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = false

    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                placeholder
                    .overlay {
                        ProgressView()
                            .tint(PirateTheme.signal)
                    }
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = Self.cache.object(forKey: url as NSURL) {
                image = cached
                return
            }
            guard !isLoading else { return }
            isLoading = true
            defer { isLoading = false }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let uiImage = UIImage(data: data) else { return }
            Self.cache.setObject(uiImage, forKey: url as NSURL)
            image = uiImage
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(PirateTheme.signal.opacity(0.05))
            .overlay {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(PirateTheme.signal.opacity(0.3))
            }
    }
}
