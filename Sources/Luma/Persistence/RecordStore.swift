import Combine
import Foundation

enum RecordStoreError: LocalizedError {
    case missingName
    case missingText

    var errorDescription: String? {
        switch self {
        case .missingName: return "请输入记录名称。"
        case .missingText: return "请输入要发送的文本。"
        }
    }
}

@MainActor
final class RecordStore: ObservableObject {
    @Published private(set) var records: [TextRecord] = []

    private let fileURL: URL
    private let secureStore: SecureTextStoring

    init(fileURL: URL? = nil, secureStore: SecureTextStoring = KeychainTextStore()) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.secureStore = secureStore
        load()
    }

    func resolvedText(for record: TextRecord) throws -> String {
        if record.isProtected {
            return try secureStore.text(for: record.id)
        }
        return record.text ?? ""
    }

    func save(_ draft: RecordDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordStoreError.missingName
        }
        guard !draft.text.isEmpty else {
            throw RecordStoreError.missingText
        }

        let oldRecord = records.first(where: { $0.id == draft.id })
        let newRecord = draft.makeRecord()

        if newRecord.isProtected {
            try secureStore.set(draft.text, for: newRecord.id)
        } else if oldRecord?.isProtected == true {
            try secureStore.delete(for: newRecord.id)
        }

        if let index = records.firstIndex(where: { $0.id == newRecord.id }) {
            records[index] = newRecord
        } else {
            records.append(newRecord)
        }
        try persist()
    }

    func delete(_ record: TextRecord) throws {
        if record.isProtected {
            try secureStore.delete(for: record.id)
        }
        records.removeAll { $0.id == record.id }
        try persist()
    }

    func toggleFavorite(_ record: TextRecord) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavorite.toggle()
        records[index].updatedAt = Date()
        try persist()
    }

    func markUsed(_ record: TextRecord) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].lastUsedAt = Date()
        records[index].useCount += 1
        try persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([TextRecord].self, from: data)
        } catch {
            records = []
            NSLog("Luma 无法读取记录库：%@", error.localizedDescription)
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Luma", isDirectory: true)
            .appendingPathComponent("records.json")
    }
}
