import SwiftUI

struct CastCarousel: View {
    let cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cast) { member in
                        castCard(member)
                    }
                }
            }
        }
    }

    private func castCard(_ member: CastMember) -> some View {
        VStack(spacing: 6) {
            if let profileUrl = member.profileUrl, let url = URL(string: profileUrl) {
                CachedImage(
                    url: url,
                    height: 80,
                    cornerRadius: 40,
                    placeholderIcon: "person.fill",
                    contentMode: .fill
                )
                .frame(width: 80)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.quaternary)
            }

            Text(member.name)
                .font(.caption.bold())
                .lineLimit(1)

            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 90)
    }
}
