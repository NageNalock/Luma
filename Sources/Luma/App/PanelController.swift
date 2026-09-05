import AppKit
import Combine
import SwiftUI

final class LumaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let state: AppState

    private let panel: LumaPanel
    private let sendTextEngine = SendTextEngine()
    private let clipboardPasteEngine = ClipboardPasteEngine()
    private var localKeyMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        panel = LumaPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        let hostingView = NSHostingView(rootView: PanelView(state: state))
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 18
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        state.onSendText = { [weak self] text, record in
            self?.send(text, record: record)
        }
        state.onPasteClipboard = { [weak self] entry in
            self?.pasteClipboardEntry(entry)
        }
        state.onRequestHide = { [weak self] in self?.hide() }
        installKeyMonitor()
        observeContentSize()
        resizePanel(for: state.mode, resultCount: state.currentResultCount, animated: false)
    }

    deinit {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let context = SourceContextCapture.capture(excludingBundleIdentifier: Bundle.main.bundleIdentifier)
        state.clipboardStore.captureLatest(sourceApplication: context?.application)
        state.prepareForPresentation(context: context)
        presentPanel()
    }

    func showWithoutSource(message: String? = nil) {
        state.prepareForPresentation(context: nil)
        state.statusMessage = message
        presentPanel()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel,
              state.editorDraft == nil,
              state.availableUpdate == nil,
              !state.showsClearClipboardConfirmation else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.panel.isVisible,
                  !self.panel.isKeyWindow,
                  self.state.editorDraft == nil,
                  self.state.availableUpdate == nil,
                  !self.state.showsClearClipboardConfirmation else {
                return
            }
            self.hide()
        }
    }

    func saveSnapshot(to url: URL) throws {
        guard let view = panel.contentView else { throw SnapshotError.missingContentView }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError.cannotCreateBitmap
        }
        view.cacheDisplay(in: bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.cannotEncodePNG
        }
        try data.write(to: url, options: .atomic)
    }

    private func presentPanel() {
        resizePanel(for: state.mode, resultCount: state.currentResultCount, animated: false)
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    private func observeContentSize() {
        Publishers.CombineLatest4(
            state.$mode,
            state.$query,
            state.recordStore.$records,
            state.clipboardStore.$entries
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] mode, query, records, clipboardEntries in
                guard let self else { return }
                let count: Int
                switch mode {
                case .records:
                    count = RecordSearch.results(for: query, in: records).count
                case .clipboard:
                    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    count = needle.isEmpty
                        ? clipboardEntries.count
                        : clipboardEntries.filter {
                            $0.text.localizedCaseInsensitiveContains(needle)
                                || ($0.sourceAppName?.localizedCaseInsensitiveContains(needle) ?? false)
                        }.count
                case .json, .diff:
                    count = 0
                }
                self.resizePanel(for: mode, resultCount: count, animated: self.panel.isVisible)
            }
            .store(in: &subscriptions)
    }

    private func resizePanel(for mode: PanelMode, resultCount: Int, animated: Bool) {
        let height: CGFloat
        switch mode {
        case .diff:
            height = 620
        case .json:
            height = 500
        case .records, .clipboard:
            let listHeight = resultCount == 0
                ? 222
                : min(390, CGFloat(resultCount * (mode == .clipboard ? 72 : 66) + 15))
            height = max(330, 106 + listHeight)
        }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let width = min(mode == .diff ? 960.0 : 720.0, visibleFrame?.width ?? 960)
        let fittedHeight = min(height, visibleFrame?.height ?? height)
        guard abs(panel.frame.height - fittedHeight) > 0.5 || abs(panel.frame.width - width) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.x = frame.midX - width / 2
        frame.origin.y = frame.maxY - fittedHeight
        frame.size = NSSize(width: width, height: fittedHeight)
        if let visibleFrame {
            frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
            frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - fittedHeight)
        }
        panel.setFrame(frame, display: panel.isVisible, animate: animated)
        panel.invalidateShadow()
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: max(visibleFrame.minY, visibleFrame.maxY - panelSize.height - min(92, visibleFrame.height * 0.12))
        )
        panel.setFrameOrigin(origin)
    }

    private func send(_ text: String, record: TextRecord) {
        guard let context = state.sourceContext else {
            state.statusMessage = "没有可用的发送目标。"
            return
        }

        guard SendTextEngine.isAccessibilityTrusted(prompt: false) else {
            state.statusMessage = "请在系统设置的“隐私与安全性 → 辅助功能”中允许 Luma，然后重试。"
            return
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != context.processIdentifier,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            state.statusMessage = SendTextError.targetChanged.localizedDescription
            return
        }

        hide()
        context.application.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            switch self.sendTextEngine.send(text, to: context) {
            case .success:
                if self.state.recordStore.records.contains(where: { $0.id == record.id }) {
                    try? self.state.recordStore.markUsed(record)
                }
            case .failure(let error):
                self.state.statusMessage = error.localizedDescription
                self.presentPanel()
            }
        }
    }

    private func pasteClipboardEntry(_ entry: ClipboardEntry) {
        do {
            try state.clipboardStore.restore(entry)
            state.selectedClipboardEntryID = entry.id
        } catch {
            state.statusMessage = error.localizedDescription
            return
        }

        guard let context = state.sourceContext else {
            state.statusMessage = "已放回剪贴板，可在目标位置按 ⌘V。"
            return
        }

        guard SendTextEngine.isAccessibilityTrusted(prompt: false) else {
            state.statusMessage = ClipboardPasteError.accessibilityPermissionRequired.localizedDescription
            return
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != context.processIdentifier,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            state.statusMessage = "发送目标已经变化；内容已放回剪贴板，可手动按 ⌘V。"
            return
        }

        hide()
        context.application.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            switch self.clipboardPasteEngine.paste(to: context) {
            case .success:
                break
            case .failure(let error):
                self.state.statusMessage = error.localizedDescription
                self.presentPanel()
            }
        }
    }

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, self.state.editorDraft == nil else { return event }

            if self.state.mode == .diff,
               event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option] {
                switch event.keyCode {
                case 126: self.state.textDiff.moveToDifference(-1); return nil
                case 125: self.state.textDiff.moveToDifference(1); return nil
                default: break
                }
            }

            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "n" where self.state.mode == .records: self.state.beginNewRecord(); return nil
                case "e" where self.state.mode == .records: self.state.beginEditingSelected(); return nil
                case "q": NSApp.terminate(nil); return nil
                case "1": self.state.switchMode(.records); return nil
                case "2": self.state.switchMode(.clipboard); return nil
                case "3": self.state.switchMode(.json); return nil
                case "4": self.state.switchMode(.diff); return nil
                default: break
                }
            }

            if event.keyCode == 53 {
                self.hide()
                return nil
            }

            guard !self.state.mode.isTextWorkbench else { return event }
            switch event.keyCode {
            case 126: self.state.moveSelection(-1); return nil
            case 125: self.state.moveSelection(1); return nil
            case 36, 76: self.state.performPrimaryAction(); return nil
            default: return event
            }
        }
    }
}

private enum SnapshotError: LocalizedError {
    case missingContentView
    case cannotCreateBitmap
    case cannotEncodePNG

    var errorDescription: String? {
        switch self {
        case .missingContentView: return "浮层没有可截图的内容。"
        case .cannotCreateBitmap: return "无法创建浮层位图。"
        case .cannotEncodePNG: return "无法编码 PNG。"
        }
    }
}
