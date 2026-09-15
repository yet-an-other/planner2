import SwiftUI
import UIKit

/// The styling inputs the Notes text view reads from the SwiftUI
/// environment. A change restyles the notes without touching the reader's
/// selection.
struct IOSEventDetailNotesStyle: Equatable {
    let contentSizeCategory: UIContentSizeCategory
    let layoutDirection: LayoutDirection
}

/// The Event Detail Popover's Notes as selectable text. SwiftUI `Text` on
/// iOS only copies a whole string, so Notes uses a non-editable UIKit text
/// view for drag-handle range selection. Only http(s) URLs link, through
/// `CalendarEventTextLinks` (the Web Experience's rule); UIKit's data
/// detectors stay off. Short notes size to fit, longer notes scroll inside
/// the section's height cap, and a dragged selection handle scrolls the
/// text view itself.
struct IOSEventDetailNotesText: UIViewRepresentable {
    let notes: String
    let maxHeight: CGFloat

    func makeUIView(context: Context) -> IOSEventDetailNotesTextView {
        IOSEventDetailNotesTextView()
    }

    func updateUIView(
        _ textView: IOSEventDetailNotesTextView,
        context: Context
    ) {
        textView.present(
            notes: notes,
            style: IOSEventDetailNotesStyle(
                contentSizeCategory: UIContentSizeCategory(
                    context.environment.dynamicTypeSize
                ),
                layoutDirection: context.environment.layoutDirection
            )
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView textView: IOSEventDetailNotesTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else {
            return nil
        }
        return CGSize(
            width: width,
            height: textView.fittingHeight(forWidth: width, maxHeight: maxHeight)
        )
    }
}

/// The Notes text view: selectable, never editable, with no data
/// detectors. A read-only UITextView leaves Select All out of its edit
/// menu, so this view adds it back; Select All → Copy is how a whole note
/// copies.
final class IOSEventDetailNotesTextView: UITextView {
    private var presentedNotes: String?
    private var presentedStyle: IOSEventDetailNotesStyle?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = true
        dataDetectorTypes = []
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        linkTextAttributes = [
            .foregroundColor: UIColor(PlannerPalette.link),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Presents the notes in the given style. When a Calendar Event Refresh
    /// leaves the notes unchanged, the reader's selection stays, even
    /// through a restyle; changed notes clear it.
    func present(notes: String, style: IOSEventDetailNotesStyle) {
        guard notes != presentedNotes || style != presentedStyle else {
            return
        }
        let keptSelection = notes == presentedNotes ? selectedRange : nil
        attributedText = Self.attributedNotes(notes, style: style)
        semanticContentAttribute = style.layoutDirection == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
        selectedRange = keptSelection ?? NSRange(location: 0, length: 0)
        presentedNotes = notes
        presentedStyle = style
    }

    /// The Notes section's height for a width: the text's own height, up
    /// to the cap beyond which the text view scrolls.
    func fittingHeight(forWidth width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let fitting = sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return min(ceil(fitting.height), maxHeight)
    }

    override func canPerformAction(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool {
        if action == #selector(selectAll(_:)) {
            return selectedRange.length < textStorage.length
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Renders the notes as the popover's subheadline ink text, with link
    /// attributes only on `CalendarEventTextLinks` URL segments. Alignment
    /// follows the layout direction, as SwiftUI's leading alignment does.
    static func attributedNotes(
        _ notes: String,
        style: IOSEventDetailNotesStyle
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.layoutDirection == .rightToLeft
            ? .right
            : .left
        paragraph.baseWritingDirection = .natural
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(
                forTextStyle: .subheadline,
                compatibleWith: UITraitCollection(
                    preferredContentSizeCategory: style.contentSizeCategory
                )
            ),
            .foregroundColor: UIColor(PlannerPalette.ink),
            .paragraphStyle: paragraph,
        ]
        return CalendarEventTextLinks.splitIntoSegments(notes).reduce(
            into: NSMutableAttributedString()
        ) { result, segment in
            switch segment {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: attributes))
            case .link(let urlText):
                var linkAttributes = attributes
                if let url = URL(string: urlText) {
                    linkAttributes[.link] = url
                }
                result.append(
                    NSAttributedString(string: urlText, attributes: linkAttributes)
                )
            }
        }
    }
}
