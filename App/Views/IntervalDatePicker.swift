import SwiftUI
import UIKit

/// The system date picker with 5-minute steps (SwiftUI's `DatePicker` can't do that).
struct IntervalDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    var mode: UIDatePicker.Mode = .time
    var style: UIDatePickerStyle = .wheels
    var minuteInterval: Int = 5
    var minimumDate: Date? = nil

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = mode
        picker.preferredDatePickerStyle = style
        picker.minuteInterval = minuteInterval
        picker.minimumDate = minimumDate
        picker.date = selection
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .vertical)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.minimumDate = minimumDate
        if abs(picker.date.timeIntervalSince(selection)) >= 1 {
            picker.setDate(selection, animated: true)
        }
    }

    /// Compact pickers get their natural size; without this SwiftUI can squeeze them to nothing
    /// (blank and untappable) or cut their text off.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        guard style == .compact else { return nil }
        let size = uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: max(size.width, 60), height: max(size.height, 34))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: IntervalDatePicker
        init(parent: IntervalDatePicker) { self.parent = parent }

        @objc func changed(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }
}

extension Date {
    /// Rounds to the nearest `step` minutes (seconds dropped), e.g. 7:03 → 7:05.
    func roundedToMinutes(_ step: Int = 5, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: self)
        let rounded = Int((Double(minute) / Double(step)).rounded()) * step
        let base = calendar.date(bySettingHour: calendar.component(.hour, from: self), minute: 0, second: 0, of: self) ?? self
        return calendar.date(byAdding: .minute, value: rounded, to: base) ?? self
    }
}
