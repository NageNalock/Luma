import SwiftUI

struct TextDiffWorkbenchView: View {
    @ObservedObject var model: TextDiffState
    let focusRequest: UUID

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                editorPane(side: .left, title: "原始文本", text: $model.leftText)
                Rectangle().fill(LumaTheme.silverline.opacity(0.75)).frame(width: 1)
                editorPane(side: .right, title: "修改后文本", text: $model.rightText)
            }
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                Text("⌥⌘↑ 上一处 · ⌥⌘↓ 下一处 · 首尾循环")
                Spacer()
                if model.result.usesCoarseComparison {
                    Text("大段改动按区块高亮")
                } else {
                    Text("精确比较空格与换行")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(LumaTheme.muted)
            .padding(.horizontal, 14)
            .frame(height: 29)
            .background(LumaTheme.mercury.opacity(0.72))
        }
        .background(LumaTheme.pearl.opacity(0.92))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isComparing ? "ellipsis.circle" : (model.result.hunks.isEmpty ? "equal.circle" : "text.badge.checkmark"))
                .foregroundStyle(LumaTheme.iris)
            Text(model.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LumaTheme.graphite)
                .lineLimit(1)
            Spacer(minLength: 8)

            if !model.result.hunks.isEmpty {
                Text("\(model.selectedHunkIndex.map { String($0 + 1) } ?? "—") / \(model.result.hunks.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LumaTheme.muted)
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                HeaderButton(title: "上一处", systemImage: "arrow.up") { model.moveToDifference(-1) }
                    .help("上一处差异（⌥⌘↑），到达首处后回到末处")
                HeaderButton(title: "下一处", systemImage: "arrow.down") { model.moveToDifference(1) }
                    .help("下一处差异（⌥⌘↓），到达末处后回到首处")
            }
            .disabled(model.isComparing || model.result.hunks.isEmpty)

            Rectangle().fill(LumaTheme.silverline).frame(width: 1, height: 18)
            HeaderButton(title: "交换", systemImage: "arrow.left.arrow.right") { model.swapTexts() }
                .disabled(model.leftText.isEmpty && model.rightText.isEmpty)
            HeaderButton(title: "清空", systemImage: "xmark") { model.clearTexts() }
                .disabled(model.leftText.isEmpty && model.rightText.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LumaTheme.silverline.opacity(0.6)).frame(height: 1)
        }
    }

    private func editorPane(side: DiffSide, title: String, text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: side == .left ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(Color(nsColor: side.color))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LumaTheme.graphite)
                if !model.result.hunks.isEmpty {
                    Text(side == .left ? "−\(model.result.removedLineCount) 行" : "+\(model.result.insertedLineCount) 行")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(nsColor: side.color))
                }
                Spacer()
                if let hunk = model.selectedHunk {
                    Text(lineDescription(side == .left ? hunk.leftLines : hunk.rightLines))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LumaTheme.muted)
                }
                Button {
                    if let pasted = NSPasteboard.general.string(forType: .string) { text.wrappedValue = pasted }
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LumaTheme.iris)
                .help("用剪贴板内容替换\(title)")
                .accessibilityLabel("粘贴到\(title)")
            }
            .padding(.horizontal, 14)
            .frame(height: 35)
            .background(LumaTheme.mercury.opacity(0.72))

            DiffTextView(
                text: text,
                side: side,
                result: model.result,
                selectedHunkIndex: model.selectedHunkIndex,
                navigationRequest: model.navigationRequest,
                focusRequest: side == .left ? focusRequest : nil
            )
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(side == .left ? "在这里粘贴原始文本…" : "在这里粘贴修改后的文本…")
                        .font(.system(size: 13))
                        .foregroundStyle(LumaTheme.muted.opacity(0.65))
                        .padding(14)
                        .padding(.leading, DiffTextView.minimumGutterWidth)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lineDescription(_ lines: Range<Int>) -> String {
        if lines.isEmpty { return "第 \(lines.lowerBound + 1) 行处" }
        if lines.count == 1 { return "第 \(lines.lowerBound + 1) 行" }
        return "第 \(lines.lowerBound + 1)–\(lines.upperBound) 行"
    }
}
