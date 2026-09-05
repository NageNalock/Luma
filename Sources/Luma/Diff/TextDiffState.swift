import AppKit
import Combine

@MainActor
final class TextDiffState: ObservableObject {
    @Published var leftText = "" {
        didSet { scheduleComparison() }
    }
    @Published var rightText = "" {
        didSet { scheduleComparison() }
    }
    @Published private(set) var result = TextDiffResult()
    @Published private(set) var isComparing = false
    @Published private(set) var selectedHunkIndex: Int?
    @Published private(set) var navigationRequest = UUID()

    private var comparisonTask: Task<Void, Never>?

    var selectedHunk: TextDiffHunk? {
        guard let selectedHunkIndex, result.hunks.indices.contains(selectedHunkIndex) else { return nil }
        return result.hunks[selectedHunkIndex]
    }

    var summary: String {
        if isComparing { return "正在对比…" }
        if leftText.isEmpty && rightText.isEmpty { return "在两侧输入或粘贴文本，自动对比" }
        if result.hunks.isEmpty { return "两段文本完全相同" }
        return "\(result.hunks.count) 处差异"
    }

    func moveToDifference(_ offset: Int) {
        guard !isComparing,
              let destination = result.destination(from: selectedHunkIndex, offset: offset) else { return }
        selectedHunkIndex = destination
        navigationRequest = UUID()
    }

    func swapTexts() {
        let previousLeft = leftText
        leftText = rightText
        rightText = previousLeft
    }

    func clearTexts() {
        leftText = ""
        rightText = ""
    }

    private func scheduleComparison() {
        comparisonTask?.cancel()
        selectedHunkIndex = nil
        result = TextDiffResult()
        let left = leftText
        let right = rightText
        guard !left.isEmpty || !right.isEmpty else {
            isComparing = false
            return
        }
        isComparing = true
        comparisonTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 180_000_000) }
            catch { return }
            let worker = Task.detached(priority: .userInitiated) {
                TextDiffer.compare(left, right)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            self.result = result
            self.isComparing = false
        }
    }
}
