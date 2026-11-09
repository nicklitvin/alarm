import SwiftUI
import WidgetKit

/// System background on the home screen, clear on the lock screen.
struct WidgetBackground: ViewModifier {
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                Color.clear
            default:
                Color(.systemBackground)
            }
        }
    }
}

extension View {
    func widgetBackground() -> some View { modifier(WidgetBackground()) }
}
