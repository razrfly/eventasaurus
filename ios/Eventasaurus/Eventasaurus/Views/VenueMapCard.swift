import SwiftUI
import MapKit

struct VenueMapCard: View {
    let name: String
    let address: String?
    let lat: Double
    let lng: Double

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Map(initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )) {
                Marker(name, coordinate: coordinate)
            }
            .frame(height: DS.ImageSize.map)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .allowsHitTesting(false)

            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(name)
                        .font(DS.Typography.bodyBold)
                    if let address, !address.isEmpty {
                        Text(address)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    openDirections()
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(DS.Typography.bodyBold)
                }
                .buttonStyle(.glassSecondary)
                .accessibilityHint("Opens Maps with directions")
            }
        }
        .padding(DS.Spacing.lg)
        .glassBackground(cornerRadius: DS.Radius.xl)
    }

    private func openDirections() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
