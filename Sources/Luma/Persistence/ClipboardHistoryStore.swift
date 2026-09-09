import AppKit
import Combine
import Foundation

enum ClipboardHistoryError: LocalizedError {
    case cannotWritePasteboard

    var errorDescription: String? {
        switch self {
        case .cannotWritePasteboard:
            return "无法把这条内容写回剪贴板。"
        }
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let fileURL: URL
    private let pasteboard: NSPasteboard
    private let maximumEntryCount: Int
    private let maximumTextSize = 1_000_000
    private var lastChangeCount: Int
    private var monitorTimer: Timer?

    init(
        fileURL: URL? = nil,
        maximumEntryCount: Int = 200,
        startMonitoring: Bool = true,
        pasteboard: NSPasteboard = .general
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.pasteboard = pasteboard
        self.maximumEntryCount = max(1, maximumEntryCount)
        lastChangeCount = pasteboard.changeCount
        load()
        if startMonitoring {
            startMonitor()
        }
    }

    deinit {
        monitorTimer?.invalidate()
    }

    func record(
        text: String,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        copiedAt: Date = Date()
    ) {
        guard !text.isEmpty, text.utf8.count <= maximumTextSize else { return }

        let existing = entries.first { $0.text == text }
        entries.removeAll { $0.text == text }
        entries.insert(
            ClipboardEntry(
                id: existing?.id ?? UUID(),
                text: text,
                copiedAt: copiedAt,
                sourceAppName: sourceAppName ?? existing?.sourceAppName,
                sourceBundleIdentifier: sourceBundleIdentifier ?? existing?.sourceBundleIdentifier
            ),
            at: 0
        )
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }
        persistLoggingFailure()
    }

    func restore(_ entry: ClipboardEntry) throws {
        try copyForPaste(entry.text)
        promote(entry)
    }

    /// Stage record/JSON text without adding another copy to clipboard history.
    func copyForPaste(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardHistoryError.cannotWritePasteboard
        }
        lastChangeCount = pasteboard.changeCount
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        persistLoggingFailure()
    }

    func clear() {
        entries.removeAll()
        persistLoggingFailure()
    }

    func captureLatest(sourceApplication: NSRunningApplication? = nil) {
        capturePasteboardChange(sourceApplication: sourceApplication)
    }

    func requestReadAccess() {
        _ = pasteboard.string(forType: .string)
    }

    private func startMonitor() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.capturePasteboardChange(sourceApplication: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func capturePasteboardChange(sourceApplication: NSRunningApplication?) {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let text = pasteboard.string(forType: .string) else { return }
        let application = sourceApplication ?? NSWorkspace.shared.frontmostApplication
        record(
            text: text,
            sourceAppName: application?.localizedName,
            sourceBundleIdentifier: application?.bundleIdentifier
        )
    }

    private func promote(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            record(
                text: entry.text,
                sourceAppName: entry.sourceAppName,
                sourceBundleIdentifier: entry.sourceBundleIdentifier
            )
            return
        }
        var promoted = entries.remove(at: index)
        promoted.copiedAt = Date()
        entries.insert(promoted, at: 0)
        persistLoggingFailure()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([ClipboardEntry].self, from: data)
            if entries.count > maximumEntryCount {
                entries.removeLast(entries.count - maximumEntryCount)
            }
        } catch {
            entries = []
            NSLog("Luma 无法读取剪贴板历史：%@", error.localizedDescription)
        }
    }

    private func persistLoggingFailure() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Luma 无法保存剪贴板历史：%@", error.localizedDescription)
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Luma", isDirectory: true)
            .appendingPathComponent("clipboard-history.json")
    }
}
