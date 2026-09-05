import AppKit
import SwiftUI

enum DiffSide {
    case left
    case right

    var color: NSColor {
        switch self {
        case .left: return NSColor(red: 0.75, green: 0.22, blue: 0.32, alpha: 1)
        case .right: return NSColor(red: 0.12, green: 0.48, blue: 0.33, alpha: 1)
        }
    }

    func range(in hunk: TextDiffHunk) -> NSRange {
        self == .left ? hunk.leftRange : hunk.rightRange
    }

    func highlights(in hunk: TextDiffHunk) -> [NSRange] {
        self == .left ? hunk.removedRanges : hunk.insertedRanges
    }
}

struct DiffTextView: NSViewRepresentable {
    static let minimumGutterWidth: CGFloat = 42

    @Binding var text: String
    let side: DiffSide
    let result: TextDiffResult
    let selectedHunkIndex: Int?
    let navigationRequest: UUID
    var focusRequest: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.clipsToBounds = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = DiffEditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(LumaTheme.graphite)
        textView.insertionPointColor = NSColor(LumaTheme.iris)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.setAccessibilityLabel(side == .left ? "原始文本" : "修改后文本")
        scrollView.documentView = textView
        scrollView.verticalRulerView = DiffLineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DiffEditorTextView else { return }
        context.coordinator.parent = self
        // Attribute changes never enter the editor's undo stack or disturb IME composition.
        if !textView.string.utf16.elementsEqual(text.utf16), !textView.hasMarkedText() {
            textView.string = text
            textView.undoManager?.removeAllActions()
            (scrollView.verticalRulerView as? DiffLineNumberRulerView)?.updateLineNumbers()
        }
        textView.apply(result: result, side: side, selectedIndex: selectedHunkIndex)

        if context.coordinator.lastNavigationRequest != navigationRequest {
            context.coordinator.lastNavigationRequest = navigationRequest
            if let selectedHunkIndex, result.hunks.indices.contains(selectedHunkIndex) {
                textView.reveal(result.hunks[selectedHunkIndex])
            }
        }
        if let focusRequest, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DiffTextView
        var lastNavigationRequest: UUID?
        var lastFocusRequest: UUID?

        init(_ parent: DiffTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            (textView.enclosingScrollView?.verticalRulerView as? DiffLineNumberRulerView)?.updateLineNumbers()
            parent.text = textView.string
        }
    }
}

private final class DiffLineNumberRulerView: NSRulerView {
    private var lineStarts = [0]
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clipsToBounds = true
        clientView = textView
        ruleThickness = DiffTextView.minimumGutterWidth
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        setAccessibilityLabel("行号")

        scrollView.contentView.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidateDisplay),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidateDisplay),
            name: NSView.frameDidChangeNotification, object: textView
        )
        updateLineNumbers()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func invalidateDisplay(_ notification: Notification) {
        needsDisplay = true
    }

    func updateLineNumbers() {
        guard let textView = clientView as? NSTextView else { return }
        let text = textView.string as NSString
        lineStarts = [0]
        var start = 0
        while start < text.length {
            var end = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            if end < text.length || contentsEnd < end { lineStarts.append(end) }
            start = end
        }
        let labelWidth = (String(lineStarts.count) as NSString).size(withAttributes: [.font: numberFont]).width
        let width = max(DiffTextView.minimumGutterWidth, ceil(labelWidth) + 20)
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(LumaTheme.mercury).withAlphaComponent(0.72).setFill()
        bounds.fill()
        NSColor(LumaTheme.silverline).withAlphaComponent(0.65).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let origin = textView.textContainerOrigin
        let visibleRect = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        layoutManager.ensureLayout(forBoundingRect: visibleRect, in: textContainer)
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let length = textView.textStorage?.length ?? 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor(LumaTheme.muted).withAlphaComponent(0.85)
        ]

        // Index logical lines, then use TextKit's actual baselines. Wrapped
        // continuations keep the same line number and do not shift later labels.
        var low = 0
        var high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= visibleCharacters.location { low = middle + 1 }
            else { high = middle }
        }
        for index in max(0, low - 1)..<lineStarts.count {
            let start = lineStarts[index]
            guard start <= NSMaxRange(visibleCharacters) else { break }
            let baseline: CGFloat
            if start < length {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                baseline = fragment.minY + layoutManager.location(forGlyphAt: glyph).y
            } else {
                baseline = layoutManager.extraLineFragmentRect.minY
                    + layoutManager.defaultBaselineOffset(for: textView.font ?? numberFont)
            }
            let point = convert(NSPoint(x: 0, y: origin.y + baseline), from: textView)
            let label = String(index + 1) as NSString
            let size = label.size(withAttributes: attributes)
            let labelRect = NSRect(
                x: bounds.maxX - size.width - 10,
                y: floor(point.y - numberFont.ascender),
                width: size.width, height: size.height
            )
            if labelRect.intersects(rect) { label.draw(at: labelRect.origin, withAttributes: attributes) }
        }
    }
}

private final class DiffEditorTextView: NSTextView {
    private var result = TextDiffResult()
    private var side = DiffSide.left
    private var selectedIndex: Int?

    func apply(result: TextDiffResult, side: DiffSide, selectedIndex: Int?) {
        self.result = result
        self.side = side
        self.selectedIndex = selectedIndex
        guard let layoutManager else { return }
        let fullRange = NSRange(location: 0, length: textStorage?.length ?? 0)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        for (index, hunk) in result.hunks.enumerated() {
            for range in side.highlights(in: hunk) where NSMaxRange(range) <= fullRange.length {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: side.color.withAlphaComponent(index == selectedIndex ? 0.30 : 0.19),
                    forCharacterRange: range
                )
            }
        }
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for (index, hunk) in result.hunks.enumerated() {
            let range = side.range(in: hunk)
            guard NSMaxRange(range) <= textStorage?.length ?? 0 else { continue }
            var band = highlightRect(for: range)
            band.origin.x = 3
            band.size.width = max(0, bounds.width - 6)
            guard band.intersects(rect) else { continue }
            let active = index == selectedIndex
            if range.length == 0 {
                // A missing side still has a visible, navigable insertion/deletion anchor.
                band.size.height = active ? 3 : 2
                side.color.withAlphaComponent(active ? 0.85 : 0.45).setFill()
                NSBezierPath(roundedRect: band, xRadius: 1, yRadius: 1).fill()
            } else {
                side.color.withAlphaComponent(active ? 0.10 : 0.05).setFill()
                NSBezierPath(roundedRect: band, xRadius: 3, yRadius: 3).fill()
                side.color.withAlphaComponent(active ? 1 : 0.5).setFill()
                NSRect(x: 3, y: band.minY, width: active ? 3 : 2, height: band.height).fill()
                if active {
                    side.color.withAlphaComponent(0.45).setStroke()
                    let outline = NSBezierPath(roundedRect: band.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                    outline.lineWidth = 1
                    outline.stroke()
                }
            }
        }
    }

    func reveal(_ hunk: TextDiffHunk) {
        guard let scrollView = enclosingScrollView else { return }
        let range = side.highlights(in: hunk).first ?? side.range(in: hunk)
        let target = NSRange(location: range.location, length: min(range.length, 1))
        scrollRangeToVisible(target)
        let rect = highlightRect(for: target)
        let viewport = scrollView.contentView.bounds
        let y = min(max(0, rect.midY - viewport.height / 2), max(0, bounds.height - viewport.height))
        // The native ruler contributes a horizontal content inset. Preserve it
        // when centering a difference so the start of each line stays visible.
        let proposedBounds = NSRect(origin: NSPoint(x: viewport.minX, y: y), size: viewport.size)
        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)
        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func highlightRect(for range: NSRange) -> NSRect {
        let lineHeight = layoutManager?.defaultLineHeight(for: font ?? .systemFont(ofSize: 13)) ?? 18
        guard let layoutManager, let textContainer else {
            return NSRect(x: 0, y: textContainerOrigin.y, width: bounds.width, height: lineHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let length = textStorage?.length ?? 0
        let origin = textContainerOrigin
        if range.length == 0 {
            if range.location == length, layoutManager.extraLineFragmentTextContainer != nil {
                return layoutManager.extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
            }
            if length == 0 {
                return NSRect(x: origin.x, y: origin.y, width: 1, height: lineHeight)
            }
            let glyph = layoutManager.glyphIndexForCharacter(at: min(range.location, length - 1))
            var rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            if range.location == length { rect.origin.y = rect.maxY }
            return rect.offsetBy(dx: origin.x, dy: origin.y)
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: origin.x, dy: origin.y)
    }
}
