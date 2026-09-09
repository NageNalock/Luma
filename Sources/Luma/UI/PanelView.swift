import SwiftUI

struct PanelView: View {
    @ObservedObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            LumaTheme.mercury.opacity(0.82)

            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(LumaTheme.silverline.opacity(0.72))
                    .frame(height: 1)

                Group {
                    switch state.mode {
                    case .records:
                        RecordListView(state: state)
                    case .clipboard:
                        ClipboardHistoryView(state: state)
                    case .json:
                        JSONWorkbenchView(state: state)
                    case .diff:
                        TextDiffWorkbenchView(model: state.textDiff, focusRequest: state.focusRequest)
                    }
                }

                TargetRailView(state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.86), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LumaTheme.silverline.opacity(0.58), lineWidth: 0.7)
                .padding(1)
        }
        .onAppear { searchFocused = !state.mode.isTextWorkbench }
        .onChange(of: state.focusRequest) { _, _ in
            searchFocused = !state.mode.isTextWorkbench
        }
        .onChange(of: state.mode) { _, mode in
            searchFocused = !mode.isTextWorkbench
        }
        .sheet(item: $state.editorDraft) { draft in
            RecordEditorView(
                initialDraft: draft,
                onSave: { state.saveDraft($0) },
                onDelete: { record in state.delete(record) },
                onCancel: { state.editorDraft = nil }
            )
        }
        .alert(item: $state.availableUpdate) { release in
            Alert(
                title: Text("发现新版本"),
                message: Text(
                    "当前版本：\(AppVersion.current.displayString)\n" +
                    "可用版本：\(release.version.displayString)" +
                    (release.isPrerelease ? "（预发布版）" : "") +
                    "\n\n下载后会校验 SHA-256，并自动打开 DMG。"
                ),
                primaryButton: .default(Text("下载并打开")) {
                    state.downloadUpdate(release)
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
        .alert("清空剪贴板历史？", isPresented: $state.showsClearClipboardConfirmation) {
            Button("清空", role: .destructive) {
                state.clearClipboardHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 Luma 在本机保存的全部剪贴板历史，且无法撤销。")
        }
    }

    @ViewBuilder
    private var header: some View {
        switch state.mode {
        case .records:
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LumaTheme.lilacWash)
                    Image(systemName: "command")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LumaTheme.iris)
                }
                .frame(width: 34, height: 34)

                TextField("搜索记录…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(LumaTheme.graphite)
                    .focused($searchFocused)
                    .onSubmit { state.performPrimaryAction() }

                HeaderButton(title: "剪贴板", systemImage: "doc.on.clipboard") {
                    state.switchMode(.clipboard)
                }

                HeaderButton(title: "JSON", systemImage: "curlybraces") {
                    state.switchMode(.json)
                }

                HeaderButton(title: "新建", systemImage: "plus") {
                    state.beginNewRecord()
                }
                HeaderButton(title: "Diff", systemImage: "arrow.left.arrow.right") {
                    state.switchMode(.diff)
                }
                .help("文本对比（⌘4）")
            }
            .padding(.horizontal, 18)
            .frame(height: 62)

        case .clipboard:
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LumaTheme.lilacWash)
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LumaTheme.iris)
                }
                .frame(width: 34, height: 34)

                TextField("搜索剪贴板历史…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(LumaTheme.graphite)
                    .focused($searchFocused)
                    .onSubmit { state.performPrimaryAction() }

                HeaderButton(title: "记录", systemImage: "text.quote") {
                    state.switchMode(.records)
                }

                HeaderButton(title: "JSON", systemImage: "curlybraces") {
                    state.switchMode(.json)
                }

                HeaderButton(title: "复制", systemImage: "doc.on.doc") {
                    state.copySelectedClipboard()
                }
                .disabled(state.selectedClipboardEntry == nil)

                HeaderButton(title: "清空", systemImage: "trash") {
                    state.showsClearClipboardConfirmation = true
                }
                .disabled(state.clipboardStore.entries.isEmpty)
                HeaderButton(title: "Diff", systemImage: "arrow.left.arrow.right") {
                    state.switchMode(.diff)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 62)

        case .json:
            HStack(spacing: 10) {
                HeaderButton(title: "记录", systemImage: "chevron.left") {
                    state.switchMode(.records)
                }

                HeaderButton(title: "剪贴板", systemImage: "doc.on.clipboard") {
                    state.switchMode(.clipboard)
                }

                Text("JSON")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(LumaTheme.graphite)
                    .help("严格校验 JSON")

                Spacer()

                Picker("缩进", selection: $state.jsonIndentWidth) {
                    Text("2 空格").tag(2)
                    Text("4 空格").tag(4)
                }
                .labelsHidden()
                .frame(width: 92)

                HeaderButton(title: "格式化", systemImage: "text.alignleft") {
                    state.formatJSON()
                }
                HeaderButton(title: "压缩", systemImage: "arrow.down.right.and.arrow.up.left") {
                    state.minifyJSON()
                }
                HeaderButton(title: "复制", systemImage: "doc.on.doc") {
                    state.copyJSONOutput()
                }
                HeaderButton(title: "Diff", systemImage: "arrow.left.arrow.right") {
                    state.switchMode(.diff)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)

        case .diff:
            HStack(spacing: 10) {
                HeaderButton(title: "记录", systemImage: "chevron.left") { state.switchMode(.records) }
                HeaderButton(title: "剪贴板", systemImage: "doc.on.clipboard") { state.switchMode(.clipboard) }
                HeaderButton(title: "JSON", systemImage: "curlybraces") { state.switchMode(.json) }
                Rectangle().fill(LumaTheme.silverline).frame(width: 1, height: 22)
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(LumaTheme.iris)
                Text("文本 Diff")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(LumaTheme.graphite)
                Spacer()
                Text("红色删除 · 绿色新增")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LumaTheme.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
        }
    }
}

struct HeaderButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(LumaTheme.graphite.opacity(0.82))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(LumaTheme.silverline.opacity(0.68), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help(title)
    }
}

private struct RecordListView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if state.filteredRecords.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ZStack {
                        Circle().fill(LumaTheme.lilacWash)
                        Image(systemName: state.query.isEmpty ? "text.badge.plus" : "magnifyingglass")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(LumaTheme.iris)
                    }
                    .frame(width: 54, height: 54)
                    Text(state.query.isEmpty ? "还没有文本记录" : "没有匹配的记录")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(LumaTheme.graphite)
                    Text(state.query.isEmpty ? "新建一条，之后可从任何应用呼出并发送。" : "试试名称、别名或标签。")
                        .font(.system(size: 12))
                        .foregroundStyle(LumaTheme.muted)
                    if state.query.isEmpty {
                        Button("新建记录") { state.beginNewRecord() }
                            .buttonStyle(.borderedProminent)
                            .tint(LumaTheme.iris)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(state.filteredRecords) { record in
                                RecordRowView(
                                    record: record,
                                    isSelected: state.selectedRecordID == record.id,
                                    onSelect: { state.selectedRecordID = record.id },
                                    onSend: {
                                        state.selectedRecordID = record.id
                                        state.sendSelected()
                                    }
                                )
                                .id(record.id)
                                .contextMenu {
                                    Button(record.isFavorite ? "取消收藏" : "收藏") {
                                        state.toggleFavorite(record)
                                    }
                                    Button("编辑") {
                                        state.selectedRecordID = record.id
                                        state.beginEditingSelected()
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: state.selectedRecordID) { _, selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(LumaTheme.pearl.opacity(0.76))
    }
}

private struct RecordRowView: View {
    let record: TextRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onSend: () -> Void

    private var preview: String {
        guard !record.hidePreview, !record.isProtected else { return "••••••••••••" }
        return (record.text ?? "")
            .replacingOccurrences(of: "\r\n", with: " ↵ ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.isFavorite ? "star.fill" : "text.quote")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(record.isFavorite ? LumaTheme.iris : LumaTheme.muted.opacity(0.72))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LumaTheme.graphite)
                    .lineLimit(1)
                Text(preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LumaTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if record.isProtected {
                Image(systemName: "key.fill")
                    .foregroundStyle(LumaTheme.iris)
            }

            ForEach(record.tags.prefix(2), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? LumaTheme.iris : LumaTheme.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isSelected ? Color.white.opacity(0.76) : LumaTheme.lilacWash)
                    .clipShape(Capsule())
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LumaTheme.iris)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 61)
        .background(isSelected ? LumaTheme.lilacWash.opacity(0.82) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? LumaTheme.iris.opacity(0.34) : Color.clear, lineWidth: 0.8)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(LumaTheme.iris)
                    .frame(width: 3, height: 35)
                    .padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onSend)
        .onTapGesture(perform: onSelect)
    }
}

private struct ClipboardHistoryView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if state.filteredClipboardEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ZStack {
                        Circle().fill(LumaTheme.lilacWash)
                        Image(systemName: state.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(LumaTheme.iris)
                    }
                    .frame(width: 54, height: 54)
                    Text(state.query.isEmpty ? "还没有剪贴板历史" : "没有匹配的剪贴板内容")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(LumaTheme.graphite)
                    Text(
                        state.query.isEmpty
                            ? "Luma 运行期间新复制的文本会自动出现在这里。"
                            : "试试搜索正文或来源应用。"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(LumaTheme.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(state.filteredClipboardEntries) { entry in
                                ClipboardRowView(
                                    entry: entry,
                                    timeReference: state.clipboardTimeReference,
                                    isSelected: state.selectedClipboardEntry?.id == entry.id,
                                    onSelect: { state.selectedClipboardEntryID = entry.id },
                                    onPaste: {
                                        state.selectedClipboardEntryID = entry.id
                                        state.pasteSelectedClipboard()
                                    }
                                )
                                .id(entry.id)
                                .contextMenu {
                                    Button("粘贴到原应用") {
                                        state.selectedClipboardEntryID = entry.id
                                        state.pasteSelectedClipboard()
                                    }
                                    Button("仅复制到剪贴板") {
                                        state.selectedClipboardEntryID = entry.id
                                        state.copySelectedClipboard()
                                    }
                                    Divider()
                                    Button("删除", role: .destructive) {
                                        state.deleteClipboardEntry(entry)
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: state.selectedClipboardEntryID) { _, selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(LumaTheme.pearl.opacity(0.76))
    }
}

private struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let timeReference: Date
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.8) : LumaTheme.mercury.opacity(0.9))
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? LumaTheme.iris : LumaTheme.muted.opacity(0.72))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.preview)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LumaTheme.graphite)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 7) {
                    if let source = entry.sourceAppName, !source.isEmpty {
                        Text(source)
                            .lineLimit(1)
                        Text("·")
                    }
                    Text(recordedTimeDescription)
                        .lineLimit(1)
                        .help("最后更新：\(entry.copiedAt.formatted(date: .numeric, time: .standard))")
                    Text("·")
                    Text("\(entry.text.count) 字符")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LumaTheme.muted)
            }

            Spacer(minLength: 12)

            if isSelected {
                HStack(spacing: 5) {
                    Text("粘贴")
                    Image(systemName: "return")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LumaTheme.iris)
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(Color.white.opacity(0.72))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 67)
        .background(isSelected ? LumaTheme.lilacWash.opacity(0.82) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? LumaTheme.iris.opacity(0.34) : Color.clear, lineWidth: 0.8)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(LumaTheme.iris)
                    .frame(width: 3, height: 39)
                    .padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPaste)
        .onTapGesture(perform: onSelect)
    }

    private var recordedTimeDescription: String {
        // Use the presentation's reference time so ordinary redraws never make the label tick.
        let elapsed = max(0, timeReference.timeIntervalSince(entry.copiedAt))
        if elapsed < 60 { return "刚刚记录" }
        if elapsed < 3_600 { return "记录于 \(Int(elapsed / 60)) 分钟前" }
        if elapsed < 86_400 { return "记录于 \(Int(elapsed / 3_600)) 小时前" }
        return "记录于 \(Int(elapsed / 86_400)) 天前"
    }
}

private struct JSONWorkbenchView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                editorPane(title: "原始内容") {
                    TextEditor(text: $state.jsonInput)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(LumaTheme.graphite)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.clear)
                }

                Rectangle()
                    .fill(LumaTheme.silverline.opacity(0.75))
                    .frame(width: 1)

                editorPane(title: "格式化结果") {
                    if state.jsonOutput.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(LumaTheme.iris.opacity(0.72))
                            Text(state.jsonInput.isEmpty ? "在左侧粘贴 JSON" : "修正错误后显示结果")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LumaTheme.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        SyntaxTextView(text: state.jsonOutput)
                    }
                }
            }

            if let diagnostic = state.jsonDiagnostic {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(LumaTheme.danger)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnostic.summary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LumaTheme.graphite)
                        if let expected = diagnostic.expected {
                            Text("此处应为 \(expected)")
                                .font(.system(size: 11))
                                .foregroundStyle(LumaTheme.muted)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(red: 1.0, green: 0.94, blue: 0.95))
                .overlay(alignment: .top) {
                    Rectangle().fill(LumaTheme.danger.opacity(0.24)).frame(height: 1)
                }
            }
        }
    }

    private func editorPane<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(LumaTheme.muted)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(LumaTheme.mercury.opacity(0.72))

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LumaTheme.pearl.opacity(0.92))
    }
}

private struct TargetRailView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LumaTheme.iris.opacity(0.8))
                .frame(height: 2)

            HStack(spacing: 9) {
                if let status = state.statusMessage {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(LumaTheme.iris)
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LumaTheme.graphite)
                        .lineLimit(1)
                } else {
                    if state.mode == .diff {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(LumaTheme.iris)
                    } else {
                        Image(nsImage: state.targetIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Text(targetDescription)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LumaTheme.graphite)
                }

                Spacer()

                if state.mode == .records {
                    Text("⌘E 编辑")
                    Text("⌘N 新建")
                } else if state.mode == .clipboard {
                    Text("双击或 ↵ 粘贴")
                } else if state.mode == .json && !state.jsonOutput.isEmpty {
                    Button("发送结果") { state.sendJSONOutput() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LumaTheme.iris)
                }

                RailActionButton(
                    title: state.isDownloadingUpdate
                        ? "下载中…"
                        : (state.isCheckingForUpdates ? "检查中…" : "更新"),
                    systemImage: "arrow.triangle.2.circlepath",
                    isWorking: state.isUpdateBusy,
                    action: state.checkForUpdates
                )
                .disabled(state.isUpdateBusy)

                RailActionButton(
                    title: "退出",
                    systemImage: "power",
                    tint: LumaTheme.danger,
                    action: state.requestQuit
                )
                .help("退出 Luma（⌘Q）")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(LumaTheme.muted)
            .padding(.horizontal, 14)
            .frame(height: 43)
            .background(.ultraThinMaterial)
        }
    }

    private var targetDescription: String {
        switch state.mode {
        case .records:
            return state.sourceContext == nil
                ? "↵ 复制记录"
                : "↵ 粘贴到 \(state.targetName)"
        case .clipboard:
            return state.sourceContext == nil
                ? "↵ 放回剪贴板"
                : "↵ 粘贴到 \(state.targetName)"
        case .json:
            return state.sourceContext == nil
                ? "复制 JSON 结果"
                : "粘贴 JSON 到 \(state.targetName)"
        case .diff:
            return "本机对比 · 内容仅保留在本次运行中"
        }
    }
}

private struct RailActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = LumaTheme.muted
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 25)
            .background(Color.white.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(LumaTheme.silverline.opacity(0.5), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }
}
