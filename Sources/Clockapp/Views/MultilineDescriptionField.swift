import SwiftUI
import AppKit

/// A multi-line text field where **Return commits** (calls `onCommit`) and
/// **Option+Return inserts a newline** — the usual chat-style behavior.
/// Also commits when editing ends (focus lost).
struct MultilineDescriptionField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmittingTextView()
        textView.delegate = context.coordinator
        textView.onCommit = { context.coordinator.onCommit() }
        textView.placeholderString = placeholder

        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 3, height: 5)

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SubmittingTextView else { return }
        context.coordinator.onCommit = onCommit
        textView.onCommit = { context.coordinator.onCommit() }
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }

        func textDidEndEditing(_ notification: Notification) {
            onCommit()
        }
    }
}

/// NSTextView that commits on Return and only inserts a newline on Option+Return.
final class SubmittingTextView: NSTextView {
    var onCommit: (() -> Void)?
    var placeholderString: String = ""

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76 // Return or numpad Enter
        if isReturn {
            if event.modifierFlags.contains(.option) {
                insertNewline(nil)
            } else {
                onCommit?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
        ]
        placeholderString.draw(at: NSPoint(x: 6, y: 5), withAttributes: attrs)
    }
}
