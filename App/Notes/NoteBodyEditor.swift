import SwiftUI
import UIKit

/// Lets the checklist button reach the text view (it needs the cursor position).
@MainActor
final class NoteEditorCommands {
    fileprivate weak var coordinator: NoteBodyEditor.Coordinator?

    /// Turns the current line(s) into checklist items, or back into text.
    func toggleChecklist() { coordinator?.toggleList(.checklist) }

    /// Turns the current line(s) into bullets (•), or back into text.
    func toggleBullets() { coordinator?.toggleList(.bullets) }
}

/// The note's body: a text view that draws checklist items (☐ / ☑ lines) as tappable boxes,
/// strikes through done items, and continues checklists and bulleted lists (•) on Return.
struct NoteBodyEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let commands: NoteEditorCommands

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = Coordinator.bodyFont
        view.adjustsFontForContentSizeCategory = true
        view.textContainer.lineFragmentPadding = 0
        // Room at the bottom so the floating buttons never cover the last lines.
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 140, right: 0)
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        context.coordinator.textView = view
        commands.coordinator = context.coordinator
        view.text = text
        context.coordinator.restyle()
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        commands.coordinator = context.coordinator
        if view.text != text {
            // Changed elsewhere (Clear, the assistant).
            view.text = text
            context.coordinator.restyle()
        }
        if isEditing, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isEditing, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: NoteBodyEditor
        weak var textView: UITextView?

        static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }

        init(parent: NoteBodyEditor) { self.parent = parent }

        // MARK: Editing

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isEditing { parent.isEditing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isEditing { parent.isEditing = false }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            // Don't touch styling while a multi-stage keyboard (e.g. Japanese) is composing.
            if textView.markedTextRange == nil { restyle() }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard range.length == 0 else { return true }
            if replacement == "\n", let result = NoteChecklist.handleReturn(in: textView.text, at: range.location) {
                replace(with: result.text, caret: result.caret)
                return false
            }
            if let result = NoteChecklist.autoBullet(in: textView.text, at: range.location, typing: replacement) {
                replace(with: result.text, caret: result.caret)
                return false
            }
            return true
        }

        func toggleList(_ style: NoteChecklist.ListStyle) {
            guard let textView else { return }
            var selection = textView.selectedRange
            var base = textView.text ?? ""
            if !textView.isFirstResponder {
                // Not typing: start a checklist on a new line at the end.
                let length = (base as NSString).length
                if !base.isEmpty, !base.hasSuffix("\n") { base += "\n" }
                selection = NSRange(location: max(length, (base as NSString).length), length: 0)
            }
            let result = NoteChecklist.toggleList(style, in: base, selection: selection)
            replace(with: result.text, caret: result.selection.location)
            if !textView.isFirstResponder { textView.becomeFirstResponder() }
        }

        private func replace(with newText: String, caret: Int) {
            guard let textView else { return }
            textView.text = newText
            textView.selectedRange = NSRange(location: min(caret, (newText as NSString).length), length: 0)
            parent.text = newText
            restyle()
            textView.scrollRangeToVisible(textView.selectedRange)
        }

        // MARK: Tapping a box

        /// Only taps on a checklist box are ours; everything else is normal text editing.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let textView else { return false }
            return boxLine(at: touch.location(in: textView), in: textView) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let textView, let lineStart = boxLine(at: recognizer.location(in: textView), in: textView),
                  let newText = NoteChecklist.toggleItem(in: textView.text, at: lineStart) else { return }
            let selection = textView.selectedRange
            textView.text = newText
            textView.selectedRange = selection // same length, so the cursor stays put
            parent.text = newText
            restyle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        /// The start of the checklist line whose box is at `point`, if any.
        private func boxLine(at point: CGPoint, in textView: UITextView) -> Int? {
            guard let position = textView.closestPosition(to: point) else { return nil }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            let text = textView.text ?? ""
            let line = NoteChecklist.lineRange(in: text, at: index)
            let kind = NoteChecklist.kind(of: (text as NSString).substring(with: line))
            guard kind == .unchecked || kind == .checked,
                  let afterBox = textView.position(from: textView.beginningOfDocument, offset: line.location + NoteChecklist.prefixLength)
            else { return nil }
            let lineRect = textView.caretRect(for: afterBox)
            // The box itself: left of the item's text, on that line.
            guard point.x <= lineRect.minX + 4, point.y >= lineRect.minY - 6, point.y <= lineRect.maxY + 6 else { return nil }
            return line.location
        }

        // MARK: Styling

        /// Orange boxes; done items struck through in gray. Styles in place, so the cursor and
        /// scroll position don't move.
        func restyle() {
            guard let textView else { return }
            let storage = textView.textStorage
            let text = textView.text ?? ""
            let font = Self.bodyFont
            let boxFont = UIFont.systemFont(ofSize: font.pointSize * 1.15, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: UIColor.label], range: NSRange(location: 0, length: storage.length))
            for line in NoteChecklist.lines(in: text) where line.kind == .unchecked || line.kind == .checked {
                storage.addAttributes([.foregroundColor: UIColor.systemOrange, .font: boxFont],
                                      range: NSRange(location: line.range.location, length: 1))
                if line.kind == .checked, line.range.length > NoteChecklist.prefixLength {
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .foregroundColor: UIColor.secondaryLabel],
                                          range: NSRange(location: line.range.location + NoteChecklist.prefixLength,
                                                         length: line.range.length - NoteChecklist.prefixLength))
                }
            }
            storage.endEditing()
            textView.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
        }
    }
}
