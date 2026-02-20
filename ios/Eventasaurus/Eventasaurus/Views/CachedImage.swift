import SwiftUI

/// Reusable image component with loading, error, and empty states.
/// Matches the web's `cdn_img` behavior: shows placeholder during load,
/// distinct error state on failure, and a fallback icon when no URL is provided.
struct CachedImage: View {
    let url: URL?
    var height: CGFloat = DS.ImageSize.cardCover
    var cornerRadius: CGFloat = DS.Radius.lg
    var placeholderIcon: String = "calendar"
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url {
            Color.clear
                .frame(height: height)
                .overlay {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(DS.Typography.title)
                                        .foregroundStyle(.tertiary)
                                }
                        case .empty:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            Rectangle()
                                .fill(.quaternary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.quaternary)
                .frame(height: height)
                .overlay {
                    Image(systemName: placeholderIcon)
                        .font(DS.Typography.title)
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
