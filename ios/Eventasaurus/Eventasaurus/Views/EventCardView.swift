import SwiftUI

struct EventCardView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image — use overlay on a fixed container so .fill doesn't blow out layout
            if let imageUrl = event.coverImageUrl, let url = URL(string: imageUrl) {
                Color.clear
                    .frame(height: 160)
                    .overlay {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "calendar")
                                        .font(.title)
                                        .foregroundStyle(.tertiary)
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Title
            Text(event.title)
                .font(.headline)
                .lineLimit(2)

            // Date
            if let date = event.startsAt {
                Text(date, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Venue
            if let venue = event.venue {
                Label(venue.name, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}
