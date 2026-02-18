import SwiftUI

struct SourceAttributionSection: View {
    let sources: [EventSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.headline)

            ForEach(sources, id: \.name) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: EventSource) -> some View {
        HStack(spacing: 10) {
            if let logoUrl = source.logoUrl, let url = URL(string: logoUrl) {
                CachedImage(
                    url: url,
                    height: 28,
                    cornerRadius: 6,
                    placeholderIcon: "building.2",
                    contentMode: .fit
                )
                .frame(width: 28)
            } else {
                Image(systemName: "building.2")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }

            Text(source.name)
                .font(.subheadline)

            Spacer()

            if let urlString = source.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
