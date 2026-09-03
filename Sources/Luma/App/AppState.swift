import AppKit
import Combine
import SwiftUI

enum PanelMode: String, CaseIterable {
    case records
    case json
}

@MainActor
final class AppState: ObservableObject {
    @Published var mode: PanelMode = .records
    @Published var query = "" {
        didSet { selectFirstResult() }
    }
    @Published var selectedRecordID: UUID?
    @Published var sourceContext: SourceContext?
    @Published var editorDraft: RecordDraft?
    @Published var statusMessage: String?
    @Published var focusRequest = UUID()
    @Published var availableUpdate: AppRelease?
    @Published var isCheckingForUpdates = false
    @Published var isDownloadingUpdate = false

    @Published var jsonInput = "" {
        didSet { scheduleJSONProcessing() }
    }
    @Published var jsonOutput = ""
    @Published var jsonDiagnostic: JSONDiagnostic?
    @Published var jsonIndentWidth = 2

    let recordStore: RecordStore
    var onSendText: ((String, TextRecord) -> Void)?
    var onRequestHide: (() -> Void)?

    private var storeSubscription: AnyCancellable?
    private var jsonTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private let updateService = GitHubUpdateService()

    init(recordStore: RecordStore) {
        self.recordStore = recordStore
        storeSubscription = recordStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        selectFirstResult()
    }

    var filteredRecords: [TextRecord] {
        RecordSearch.results(for: query, in: recordStore.records)
    }

    var selectedRecord: TextRecord? {
        guard let selectedRecordID else { return filteredRecords.first }
        return filteredRecords.first { $0.id == selectedRecordID }
    }

    var targetName: String {
        sourceContext?.displayName ?? "原应用"
    }

    var targetIcon: NSImage {
        sourceContext?.icon ?? NSImage(systemSymbolName: "arrow.turn.down.left", accessibilityDescription: nil)!
    }

    var isUpdateBusy: Bool {
        isCheckingForUpdates || isDownloadingUpdate
    }

    func prepareForPresentation(context: SourceContext?) {
        sourceContext = context
        query = ""
        statusMessage = nil
        editorDraft = nil
        selectFirstResult()
        focusRequest = UUID()
    }

    func switchMode(_ newMode: PanelMode) {
        mode = newMode
        statusMessage = nil
        focusRequest = UUID()
    }

    func moveSelection(_ offset: Int) {
        let results = filteredRecords
        guard !results.isEmpty else { selectedRecordID = nil; return }
        let currentIndex = selectedRecordID.flatMap { id in results.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(0, currentIndex + offset), results.count - 1)
        selectedRecordID = results[next].id
    }

    func sendSelected() {
        guard let record = selectedRecord else { return }
        guard let context = sourceContext else {
            statusMessage = "没有可用的发送目标。"
            return
        }
        if !record.allowedBundleIdentifiers.isEmpty,
           !record.allowedBundleIdentifiers.contains(context.bundleIdentifier) {
            statusMessage = "这条记录不允许发送到 \(context.displayName)。"
            return
        }

        do {
            var text = try recordStore.resolvedText(for: record)
            if record.interpretEscapes {
                text = EscapeSequenceParser.parse(text)
            }
            onSendText?(text, record)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func beginNewRecord() {
        editorDraft = RecordDraft()
    }

    func beginEditingSelected() {
        guard let record = selectedRecord else { return }
        do {
            editorDraft = RecordDraft(record: record, resolvedText: try recordStore.resolvedText(for: record))
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveDraft(_ draft: RecordDraft) -> Bool {
        do {
            try recordStore.save(draft)
            editorDraft = nil
            selectedRecordID = draft.id
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ record: TextRecord) {
        do {
            try recordStore.delete(record)
            editorDraft = nil
            selectFirstResult()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ record: TextRecord) {
        do {
            try recordStore.toggleFavorite(record)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func markSelectedUsed() {
        guard let record = selectedRecord else { return }
        try? recordStore.markUsed(record)
    }

    func checkForUpdates() {
        guard !isUpdateBusy else { return }
        isCheckingForUpdates = true
        statusMessage = "正在检查 GitHub Release…"

        updateTask = Task { [weak self] in
            guard let self else { return }
            defer { isCheckingForUpdates = false }
            do {
                let release = try await updateService.newestRelease()
                if release.version > AppVersion.current {
                    availableUpdate = release
                    statusMessage = "发现新版本 \(release.version.displayString)。"
                } else {
                    statusMessage = "当前已是最新版本（\(AppVersion.current.displayString)）。"
                }
            } catch {
                statusMessage = "检查更新失败：\(error.localizedDescription)"
            }
        }
    }

    func downloadUpdate(_ release: AppRelease) {
        guard !isUpdateBusy else { return }
        isDownloadingUpdate = true
        statusMessage = "正在下载并校验 \(release.dmgName)…"

        updateTask = Task { [weak self] in
            guard let self else { return }
            defer { isDownloadingUpdate = false }
            do {
                let fileURL = try await updateService.download(release)
                guard NSWorkspace.shared.open(fileURL) else {
                    throw GitHubUpdateError.cannotOpenDownload
                }
                statusMessage = "新版本已下载并打开，请将 Luma 拖入“应用程序”。"
            } catch {
                statusMessage = "下载更新失败：\(error.localizedDescription)"
            }
        }
    }

    func requestQuit() {
        NSApp.terminate(nil)
    }

    func formatJSON() {
        processJSON(pretty: true)
    }

    func minifyJSON() {
        processJSON(pretty: false)
    }

    func copyJSONOutput() {
        guard !jsonOutput.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonOutput, forType: .string)
        statusMessage = "已复制 JSON。"
    }

    func sendJSONOutput() {
        guard !jsonOutput.isEmpty else { return }
        let synthetic = TextRecord(name: "JSON 结果", text: jsonOutput)
        onSendText?(jsonOutput, synthetic)
    }

    private func selectFirstResult() {
        let results = RecordSearch.results(for: query, in: recordStore.records)
        if !results.contains(where: { $0.id == selectedRecordID }) {
            selectedRecordID = results.first?.id
        }
    }

    private func scheduleJSONProcessing() {
        jsonTask?.cancel()
        let input = jsonInput
        let indentWidth = jsonIndentWidth
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            jsonOutput = ""
            jsonDiagnostic = nil
            return
        }

        jsonTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                let diagnostic = JSONDiagnosticParser.validate(input)
                let output = diagnostic == nil ? (try? JSONTextFormatter.pretty(input, indentWidth: indentWidth)) : nil
                return (diagnostic, output)
            }.value
            guard !Task.isCancelled, self?.jsonInput == input else { return }
            self?.jsonDiagnostic = result.0
            self?.jsonOutput = result.1 ?? ""
        }
    }

    private func processJSON(pretty: Bool) {
        do {
            jsonOutput = pretty
                ? try JSONTextFormatter.pretty(jsonInput, indentWidth: jsonIndentWidth)
                : try JSONTextFormatter.minified(jsonInput)
            jsonDiagnostic = nil
            statusMessage = nil
        } catch JSONFormattingError.invalid(let diagnostic) {
            jsonDiagnostic = diagnostic
            statusMessage = diagnostic.summary
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
