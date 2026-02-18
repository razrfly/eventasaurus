import SwiftUI

struct ExternalLinkButton: View {
    let title: String
    let url: URL
    var icon: String = "arrow.up.right.square"

    var body: some View {
        Link(destination: url) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
