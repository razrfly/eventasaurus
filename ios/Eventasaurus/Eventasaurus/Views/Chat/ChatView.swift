import SwiftUI

struct ChatView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "message",
                title: "Chat Coming Soon",
                message: "Connect with hosts and fellow attendees."
            )
            .navigationTitle("Chat")
            .toolbar(.hidden, for: .tabBar)
        }
    }
}
