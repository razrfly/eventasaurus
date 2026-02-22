import SwiftUI
import UIKit

/// A date picker that enforces 30-minute intervals using UIDatePicker's `minuteInterval`.
/// SwiftUI's native DatePicker doesn't expose this property, so we wrap UIKit.
struct DatePicker30Min: UIViewRepresentable {
    @Binding var selection: Date
    var minimumDate: Date?

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 30
        picker.minimumDate = minimumDate
        picker.date = selection
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.dateChanged(_:)),
            for: .valueChanged
        )
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        picker.minimumDate = minimumDate

        // Guard against feedback loops: only update if meaningfully different
        guard !context.coordinator.isUpdating else { return }
        if abs(picker.date.timeIntervalSince(selection)) > 1 {
            picker.date = selection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        var selection: Binding<Date>
        var isUpdating = false

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func dateChanged(_ picker: UIDatePicker) {
            isUpdating = true
            selection.wrappedValue = picker.date
            isUpdating = false
        }
    }
}

/// A form row that pairs a label with a 30-minute interval date picker.
/// Replicates the layout of SwiftUI's native DatePicker form rows.
struct DatePicker30MinRow: View {
    let label: String
    @Binding var selection: Date
    var minimumDate: Date?

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Typography.body)
            Spacer()
            DatePicker30Min(selection: $selection, minimumDate: minimumDate)
                .fixedSize()
        }
    }
}
