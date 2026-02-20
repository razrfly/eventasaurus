import SwiftUI

struct CastCarousel: View {
    let cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Cast")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.lg) {
                    ForEach(cast) { member in
                        castCard(member)
                    }
                }
            }
        }
    }

    private func castCard(_ member: CastMember) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            if let profileUrl = member.profileUrl, let url = URL(string: profileUrl) {
                CachedImage(
                    url: url,
                    height: DS.ImageSize.avatarLarge,
                    cornerRadius: 0,
                    placeholderIcon: "person.fill",
                    contentMode: .fill
                )
                .frame(width: DS.ImageSize.avatarLarge)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: DS.ImageSize.avatarLarge, height: DS.ImageSize.avatarLarge)
                    .foregroundStyle(.quaternary)
            }

            Text(member.name)
                .font(DS.Typography.captionBold)
                .lineLimit(1)

            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: DS.ImageSize.castCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(castAccessibilityLabel(member))
    }

    private func castAccessibilityLabel(_ member: CastMember) -> String {
        if let character = member.character, !character.isEmpty {
            return String(localized: "\(member.name) as \(character)")
        }
        return member.name
    }
}
