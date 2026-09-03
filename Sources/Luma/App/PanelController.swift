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
        state.onRequestHide = { [weak self] in self?.hide() }
        installKeyMonitor()
        observeContentSize()
        resizePanel(for: state.mode, resultCount: state.filteredRecords.count, animated: false)
    }

    deinit {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let context = SourceContextCapture.capture(excludingBundleIdentifier: Bundle.main.bundleIdentifier)
        state.prepareForPresentation(context: context)
        presentPanel()
    }

    func showWithoutSource(message: String) {
        state.prepareForPresentation(context: nil)
        state.statusMessage = message
        presentPanel()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, state.editorDraft == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow, self.state.editorDraft == nil else {
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
        resizePanel(for: state.mode, resultCount: state.filteredRecords.count, animated: false)
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    private func observeContentSize() {
        Publishers.CombineLatest3(state.$mode, state.$query, state.recordStore.$records)
            .receive(on: RunLoop.main)
            .sink { [weak self] values in
                guard let self else { return }
                let (mode, query, records) = values
                let count = mode == .records ? RecordSearch.results(for: query, in: records).count : 0
                self.resizePanel(for: mode, resultCount: count, animated: self.panel.isVisible)
            }
            .store(in: &subscriptions)
    }

    private func resizePanel(for mode: PanelMode, resultCount: Int, animated: Bool) {
        let height: CGFloat
        switch mode {
        case .json:
            height = 500
        case .records:
            let listHeight = resultCount == 0
                ? 222
                : min(390, CGFloat(resultCount * 66 + 15))
            height = max(330, 106 + listHeight)
        }

        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
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
            y: visibleFrame.maxY - panelSize.height - min(92, visibleFrame.height * 0.12)
        )
        panel.setFrameOrigin(origin)
    }

    private func send(_ text: String, record: TextRecord) {
        guard let context = state.sourceContext else {
            state.statusMessage = "没有可用的发送目标。"
            return
        }

        guard SendTextEngine.isAccessibilityTrusted(prompt: true) else {
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

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, self.state.editorDraft == nil else { return event }

            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "n": self.state.beginNewRecord(); return nil
                case "e" where self.state.mode == .records: self.state.beginEditingSelected(); return nil
                case "q": NSApp.terminate(nil); return nil
                case "1": self.state.switchMode(.records); return nil
                case "2": self.state.switchMode(.json); return nil
                default: break
                }
            }

            if event.keyCode == 53 {
                self.hide()
                return nil
            }

            guard self.state.mode == .records else { return event }
            switch event.keyCode {
            case 126: self.state.moveSelection(-1); return nil
            case 125: self.state.moveSelection(1); return nil
            case 36, 76: self.state.sendSelected(); return nil
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
