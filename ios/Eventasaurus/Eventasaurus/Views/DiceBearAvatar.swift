import SwiftUI

/// Loads a DiceBear Dylan-style avatar as PNG.
/// Uses URLSession directly because AsyncImage can fail on some CDN responses.
struct DiceBearAvatar: View {
    let email: String
    var size: CGFloat = 48

    @State private var image: UIImage?
    @State private var isLoading = true

    private var avatarURL: URL? {
        let seed = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return URL(string: "https://api.dicebear.com/9.x/dylan/png?seed=\(seed)&size=\(Int(size * 2))")
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .task(id: email) {
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
        } catch {
            isLoading = false
        }
    }
}
