import SwiftUI

struct SourceAttributionSection: View {
    let sources: [EventSource]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Sources")

            ForEach(sources) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: EventSource) -> some View {
        HStack(spacing: DS.Spacing.lg) {
            if let logoUrl = source.logoUrl, let url = URL(string: logoUrl) {
                CachedImage(
                    url: url,
                    height: DS.ImageSize.logoSmall,
                    cornerRadius: DS.Radius.sm,
                    placeholderIcon: "building.2",
                    contentMode: .fit
                )
                .frame(width: DS.ImageSize.logoSmall)
            } else {
                Image(systemName: "building.2")
                    .font(DS.Typography.prose)
                    .frame(width: DS.ImageSize.logoSmall, height: DS.ImageSize.logoSmall)
                    .foregroundStyle(.secondary)
            }

            Text(source.name)
                .font(DS.Typography.body)

            Spacer()

            if let urlString = source.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(DS.Typography.body)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
