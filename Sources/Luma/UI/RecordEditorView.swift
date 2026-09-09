import SwiftUI

struct RecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecordDraft
    @State private var localError: String?

    let onSave: (RecordDraft) -> Bool
    let onDelete: (TextRecord) -> Void
    let onCancel: () -> Void

    init(
        initialDraft: RecordDraft,
        onSave: @escaping (RecordDraft) -> Bool,
        onDelete: @escaping (TextRecord) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.originalRecord == nil ? "新建文本记录" : "编辑文本记录")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(LumaTheme.graphite)
                    Text("选择后，正文会原样发送到此前聚焦的位置。")
                        .font(.system(size: 11))
                        .foregroundStyle(LumaTheme.muted)
                }
                Spacer()
            }
            .padding(20)

            Rectangle().fill(LumaTheme.silverline.opacity(0.7)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldLabel("名称")
                    TextField("例如：常用回复", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .lumaCard()

                    fieldLabel("要发送的文本")
                    TextEditor(text: $draft.text)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 150)
                        .lumaCard()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            fieldLabel("别名")
                            TextField("reply, hello", text: $draft.aliasesText)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .lumaCard()
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            fieldLabel("标签")
                            TextField("常用, 文本", text: $draft.tagsText)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .lumaCard()
                        }
                    }

                    VStack(spacing: 0) {
                        optionRow(
                            title: "解析控制字符",
                            detail: "将 \\n、\\t 等转换为换行、制表符等文本字符",
                            isOn: $draft.interpretEscapes
                        )
                        Divider().padding(.leading, 14)
                        optionRow(
                            title: "隐藏预览",
                            detail: "在搜索结果中用圆点代替正文",
                            isOn: $draft.hidePreview
                        )
                        Divider().padding(.leading, 14)
                        optionRow(
                            title: "存入钥匙串",
                            detail: "正文不写入记录数据库，并自动隐藏预览",
                            isOn: $draft.isProtected
                        )
                    }
                    .lumaCard()

                    DisclosureGroup("限制目标应用") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("填写允许接收此记录的 bundle identifier，用逗号分隔；留空表示不限。")
                                .font(.system(size: 11))
                                .foregroundStyle(LumaTheme.muted)
                            TextField("com.example.target", text: $draft.allowedAppsText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .lumaCard()
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 12, weight: .semibold))

                    if let localError {
                        Label(localError, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LumaTheme.danger)
                    }
                }
                .padding(20)
            }

            Rectangle().fill(LumaTheme.silverline.opacity(0.7)).frame(height: 1)

            HStack {
                if let original = draft.originalRecord {
                    Button("删除", role: .destructive) {
                        onDelete(original)
                        dismiss()
                    }
                }
                Spacer()
                Button("取消") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(LumaTheme.iris)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 590)
        .background(LumaTheme.mercury)
    }

    private func save() {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localError = "请输入记录名称。"
            return
        }
        guard !draft.text.isEmpty else {
            localError = "请输入要发送的文本。"
            return
        }
        if onSave(draft) {
            dismiss()
        } else {
            localError = "保存失败，请查看主窗口提示。"
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(LumaTheme.muted)
    }

    private func optionRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LumaTheme.graphite)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(LumaTheme.muted)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
    }
}
