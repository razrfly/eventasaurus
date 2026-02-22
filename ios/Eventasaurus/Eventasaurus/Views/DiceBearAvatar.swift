import SwiftUI

/// Loads a DiceBear Dylan-style avatar as PNG.
/// Uses URLSession directly because AsyncImage can fail on some CDN responses.
struct DiceBearAvatar: View {
    var email: String? = nil
    var url: URL? = nil
    var size: CGFloat = 48

    @State private var image: UIImage?
    @State private var isLoading = true

    private var avatarURL: URL? {
        if let url {
            // Backend returns SVG URLs but UIImage needs PNG — swap only the path component
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               components.host?.contains("api.dicebear.com") == true {
                let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: false)
                if let idx = pathParts.lastIndex(of: "svg") {
                    var mutable = pathParts
                    mutable[idx] = "png"
                    components.path = mutable.joined(separator: "/")
                    return components.url ?? url
                }
            }
            return url
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

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let uiImage = UIImage(data: data) else {
                isLoading = false
                return
            }
            image = uiImage
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
