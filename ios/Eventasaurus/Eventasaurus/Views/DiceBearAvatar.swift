import SwiftUI

/// Loads a DiceBear Dylan-style avatar as PNG.
/// Uses URLSession directly because AsyncImage can fail on some CDN responses.
struct DiceBearAvatar: View {
    var email: String? = nil
    var url: URL? = nil
    var size: CGFloat = 48

    @State private var image: UIImage?
    @State private var isLoading = true

    // Shared cache persists across view lifecycles for the app session.
    // nonisolated(unsafe) because NSCache is thread-safe by design.
    nonisolated(unsafe) private static let imageCache = NSCache<NSString, UIImage>()

    // Extracted so prefetch() can reuse the same SVG→PNG transformation.
    // nonisolated because it's pure URL math with no actor state.
    fileprivate nonisolated static func pngURL(from inputURL: URL) -> URL {
        if var components = URLComponents(url: inputURL, resolvingAgainstBaseURL: false),
           components.host?.contains("api.dicebear.com") == true {
            let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: false)
            if let idx = pathParts.lastIndex(of: "svg") {
                var mutable = pathParts
                mutable[idx] = "png"
                components.path = mutable.joined(separator: "/")
                return components.url ?? inputURL
            }
        }
        return inputURL
    }

    private var avatarURL: URL? {
        if let url {
            return DiceBearAvatar.pngURL(from: url)
        }
        guard let email else { return nil }
        // Use a strict character set that also encodes '+' (which .urlQueryAllowed leaves unescaped)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("+")
        let seed = email.addingPercentEncoding(withAllowedCharacters: allowed) ?? email
        return URL(string: "https://api.dicebear.com/9.x/dylan/png?seed=\(seed)&size=\(Int(size * 2))")
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .task(id: email ?? url?.absoluteString) {
            await loadAvatar()
        }
    }

    private func loadAvatar() async {
        guard let url = avatarURL else {
            isLoading = false
            return
        }
        let key = url.absoluteString as NSString
        if let cached = DiceBearAvatar.imageCache.object(forKey: key) {
            image = cached
            isLoading = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let uiImage = UIImage(data: data) else {
                isLoading = false
                return
            }
            DiceBearAvatar.imageCache.setObject(uiImage, forKey: key)
            image = uiImage
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    /// Warms the NSCache for a batch of avatar URLs concurrently.
    /// Call this before rendering a list of avatars so images are ready on first render.
    nonisolated static func prefetch(avatarUrls: [URL]) async {
        let maxConcurrent = 6
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for inputURL in avatarUrls {
                if active >= maxConcurrent {
                    await group.next()
                    active -= 1
                }
                group.addTask {
                    let url = pngURL(from: inputURL)
                    let key = url.absoluteString as NSString
                    guard imageCache.object(forKey: key) == nil else { return }
                    guard let (data, response) = try? await URLSession.shared.data(from: url),
                          let http = response as? HTTPURLResponse,
                          200..<300 ~= http.statusCode,
                          let uiImage = UIImage(data: data) else { return }
                    imageCache.setObject(uiImage, forKey: key)
                }
                active += 1
            }
        }
    }
}
