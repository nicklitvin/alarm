import SwiftUI

/// A large, thumb-friendly "New …" button pinned above the tab bar.
struct BottomActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .shadow(color: .orange.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
