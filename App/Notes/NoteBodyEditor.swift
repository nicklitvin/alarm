import SwiftUI
import UIKit

/// Lets the checklist button reach the text view (it needs the cursor position).
@MainActor
final class NoteEditorCommands {
    fileprivate weak var coordinator: NoteBodyEditor.Coordinator?

    /// Turns the current line(s) into a numbered, bulleted or checklist list, or back into text.
    func toggleList(_ style: NoteChecklist.ListStyle) { coordinator?.toggleList(style) }

    /// Starts typing at the beginning of the first line (Return in the title).
    func editFirstLine() { coordinator?.editFirstLine() }
}

/// The note's body: a text view that draws checklist items (☐ / ☑ lines) as tappable boxes,
/// strikes through done items, and continues checklists and bulleted lists (•) on Return.
/// A text view that draws round checkboxes (like the To-Do tab's) over checklist items. The box
/// characters stay in the text, invisible, so the note's text and copying are unchanged.
final class ChecklistTextView: UITextView {
    private var circles: [UIImageView] = []
    /// Pictures, drawn over their hidden "[image:…]" lines.
    private var pictures: [UIImageView] = []
    private var lastWidth: CGFloat = 0

    /// Pasting a picture (the coordinator saves it and puts it in the text).
    var onPasteImage: ((UIImage) -> Void)?
    /// The width changed (rotation, Split View): pictures need new heights.
    var onWidthChange: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            onWidthChange?()
        }
        updateCircles()
        updatePictures()
    }

    // MARK: Pasting pictures

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if UIPasteboard.general.hasImages, let image = UIPasteboard.general.image {
            onPasteImage?(image)
        } else {
            super.paste(sender)
        }
    }

    // MARK: Showing pictures

    /// The width pictures are shown at: the text's width.
    var pictureWidth: CGFloat { max(120, bounds.width - textContainerInset.left - textContainerInset.right) }

    /// A picture's size in the note: the text's width, at most 420 pt tall.
    static func pictureSize(for image: UIImage, width: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return CGSize(width: width, height: 200) }
        let height = width * image.size.height / image.size.width
        return height <= 420 ? CGSize(width: width, height: height)
            : CGSize(width: width * 420 / height, height: 420)
    }

    /// Puts each picture over its line (the line is as tall as the picture; see restyle).
    func updatePictures() {
        let lines = NoteImageText.images(in: text ?? "")
        while pictures.count < lines.count {
            let view = UIImageView()
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.layer.cornerRadius = 12
            view.layer.cornerCurve = .continuous
            view.isUserInteractionEnabled = false
            addSubview(view)
            pictures.append(view)
        }
        for (index, view) in pictures.enumerated() {
            guard index < lines.count,
                  let image = NoteImageStore.image(lines[index].id),
                  let top = lineTop(atOffset: lines[index].range.location) else {
                view.isHidden = true
                continue
            }
            view.image = image
            let size = Self.pictureSize(for: image, width: pictureWidth)
            view.frame = CGRect(x: textContainerInset.left, y: top + 4, width: size.width, height: size.height)
            view.isHidden = false
        }
    }

    /// The top (in this view's coordinates) of the line that starts at `offset`.
    private func lineTop(atOffset offset: Int) -> CGFloat? {
        guard let layout = textLayoutManager,
              let content = layout.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset) else { return nil }
        layout.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layout.textLayoutFragment(for: location) else { return nil }
        return fragment.layoutFragmentFrame.minY + textContainerInset.top
    }

    /// Puts a circle (or a filled orange checkmark) over each checklist item's box.
    func updateCircles() {
        let text = self.text ?? ""
        let items = NoteChecklist.lines(in: text).filter { $0.kind == .unchecked || $0.kind == .checked }
        while circles.count < items.count {
            let image = UIImageView()
            image.contentMode = .scaleAspectFit
            image.isUserInteractionEnabled = false
            addSubview(image)
            circles.append(image)
        }
        let size = (font?.pointSize ?? 17) * 1.25
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: size * 0.9, weight: .regular)
        for (index, circle) in circles.enumerated() {
            guard index < items.count,
                  let start = position(from: beginningOfDocument, offset: items[index].range.location),
                  let end = position(from: start, offset: 1),
                  let range = textRange(from: start, to: end) else {
                circle.isHidden = true
                continue
            }
            let box = firstRect(for: range)
            guard !box.isNull, !box.isInfinite else { circle.isHidden = true; continue }
            let checked = items[index].kind == .checked
            circle.image = UIImage(systemName: checked ? "checkmark.circle.fill" : "circle", withConfiguration: symbolConfig)
            circle.tintColor = checked ? .systemOrange : .secondaryLabel
            // Center on the text's capital letters (from the line's baseline), not on the box
            // character's line box: ☐ comes from a symbol font with a taller line.
            let capHeight = (font ?? UIFont.preferredFont(forTextStyle: .body)).capHeight
            let fromBaseline = baseline(atOffset: items[index].range.location).map { $0 - capHeight / 2 }
            let centerY = fromBaseline.flatMap { (box.minY...box.maxY).contains($0) ? $0 : nil } ?? box.midY
            circle.frame = CGRect(x: box.midX - size / 2, y: centerY - size / 2, width: size, height: size)
            circle.isHidden = false
        }
    }

    /// The baseline (in this view's coordinates) of the line that starts at `offset`.
    private func baseline(atOffset offset: Int) -> CGFloat? {
        guard let layout = textLayoutManager,
              let content = layout.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset) else { return nil }
        layout.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layout.textLayoutFragment(for: location),
              let line = fragment.textLineFragments.first else { return nil }
        return fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
            + textContainerInset.top
    }
}

struct NoteBodyEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let commands: NoteEditorCommands

    func makeUIView(context: Context) -> UITextView {
        let view = ChecklistTextView()
        view.backgroundColor = .clear
        view.font = Coordinator.bodyFont
        view.adjustsFontForContentSizeCategory = true
        view.textContainer.lineFragmentPadding = 0
        // Room at the bottom so the floating buttons never cover the last lines.
        // 20 pt side margins inside the text view (not around it), so the scroll bar is at the edge.
        view.textContainerInset = UIEdgeInsets(top: 8, left: 20, bottom: 140, right: 20)
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = true
        view.addGestureRecognizer(tap)

        context.coordinator.textView = view
        commands.coordinator = context.coordinator
        view.onPasteImage = { [weak coordinator = context.coordinator] image in coordinator?.pasteImage(image) }
        view.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.restyle() }
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
            let text = textView.text ?? ""
            // A picture is deleted whole (its hidden "[image:…]" line), never a few characters of it.
            if replacement.isEmpty, let expanded = NoteImageText.expandedDeletion(range, in: text), expanded != range {
                replace(with: (text as NSString).replacingCharacters(in: expanded, with: ""), caret: expanded.location)
                return false
            }
            // Typing on a picture's line goes on a line of its own, below it (or above, at its start).
            if !replacement.isEmpty, range.length == 0,
               let line = NoteImageText.images(in: text).first(where: { range.location >= $0.range.location && range.location <= NSMaxRange($0.range) })?.range {
                let ns = text as NSString
                if range.location == line.location {
                    let insert = replacement == "\n" ? "\n" : replacement + "\n"
                    replace(with: ns.replacingCharacters(in: NSRange(location: line.location, length: 0), with: insert),
                            caret: line.location + (insert as NSString).length - 1)
                } else if NSMaxRange(line) < ns.length {
                    let at = NSMaxRange(line) + 1
                    replace(with: ns.replacingCharacters(in: NSRange(location: at, length: 0), with: replacement),
                            caret: at + (replacement as NSString).length)
                } else {
                    let newText = text + "\n" + (replacement == "\n" ? "" : replacement)
                    replace(with: newText, caret: (newText as NSString).length)
                }
                return false
            }
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

        /// Paste: the picture is saved and goes on a line of its own at the cursor.
        func pasteImage(_ image: UIImage) {
            guard let textView, let id = NoteImageStore.save(image) else { return }
            var text = textView.text ?? ""
            let selection = textView.selectedRange
            if selection.length > 0 { text = (text as NSString).replacingCharacters(in: selection, with: "") }
            let result = NoteImageText.inserting(id, into: text, at: selection.location)
            replace(with: result.text, caret: result.caret)
        }

        func toggleList(_ style: NoteChecklist.ListStyle) {
            guard let textView else { return }
            var selection = textView.selectedRange
            var base = textView.text ?? ""
            if !textView.isFirstResponder {
                // Not typing: start the list on a new line at the end.
                let length = (base as NSString).length
                if !base.isEmpty, !base.hasSuffix("\n") { base += "\n" }
                selection = NSRange(location: max(length, (base as NSString).length), length: 0)
            }
            let result = NoteChecklist.toggleList(style, in: base, selection: selection)
            replace(with: result.text, caret: result.selection.location)
            if !textView.isFirstResponder { textView.becomeFirstResponder() }
        }

        func editFirstLine() {
            guard let textView else { return }
            textView.selectedRange = NSRange(location: NoteChecklist.firstLineCaret(in: textView.text ?? ""), length: 0)
            if !textView.isFirstResponder { textView.becomeFirstResponder() }
            textView.scrollRangeToVisible(textView.selectedRange)
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

        /// A tap on a box must reach us before the text view's own taps (which would just move the
        /// cursor or start editing). Elsewhere we decline the touch, so they work as usual.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view === textView
        }

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
            // The box itself (with some room around it): left of the item's text, on that line.
            guard point.x <= lineRect.minX + 10, point.y >= lineRect.minY - 8, point.y <= lineRect.maxY + 8 else { return nil }
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
            let boxFont = UIFont.systemFont(ofSize: font.pointSize * 1.3, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: UIColor.label], range: NSRange(location: 0, length: storage.length))
            for line in NoteChecklist.lines(in: text) where line.kind == .unchecked || line.kind == .checked {
                // The box character is invisible: a round checkbox is drawn over it.
                storage.addAttributes([.foregroundColor: UIColor.clear, .font: boxFont],
                                      range: NSRange(location: line.range.location, length: 1))
                if line.kind == .checked, line.range.length > NoteChecklist.prefixLength {
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .foregroundColor: UIColor.secondaryLabel],
                                          range: NSRange(location: line.range.location + NoteChecklist.prefixLength,
                                                         length: line.range.length - NoteChecklist.prefixLength))
                }
            }
            // Picture lines: their "[image:…]" text is hidden and the line is as tall as the
            // picture drawn over it.
            if let checklistView = textView as? ChecklistTextView {
                for picture in NoteImageText.images(in: text) {
                    guard let image = NoteImageStore.image(picture.id) else { continue }
                    let height = ChecklistTextView.pictureSize(for: image, width: checklistView.pictureWidth).height + 8
                    let style = NSMutableParagraphStyle()
                    style.minimumLineHeight = height
                    style.maximumLineHeight = height
                    storage.addAttributes([.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 2),
                                           .paragraphStyle: style], range: picture.range)
                }
            }
            storage.endEditing()
            textView.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
            (textView as? ChecklistTextView)?.setNeedsLayout() // move the round checkboxes
        }
    }
}
