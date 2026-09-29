import Foundation

enum RecordKind: String, Codable, CaseIterable {
    case text
    case script
    case command

    var title: String {
        switch self {
        case .text: return "快捷文本"
        case .script: return "脚本文件"
        case .command: return "Shell 命令"
        }
    }

    var isLauncher: Bool { self != .text }
}

struct TextRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var text: String?
    var kind: RecordKind
    var aliases: [String]
    var tags: [String]
    var isFavorite: Bool
    var interpretEscapes: Bool
    var hidePreview: Bool
    var isProtected: Bool
    var allowedBundleIdentifiers: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        text: String,
        kind: RecordKind = .text,
        aliases: [String] = [],
        tags: [String] = [],
        isFavorite: Bool = false,
        interpretEscapes: Bool = false,
        hidePreview: Bool = false,
        isProtected: Bool = false,
        allowedBundleIdentifiers: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.kind = kind
        self.aliases = aliases
        self.tags = tags
        self.isFavorite = isFavorite
        self.interpretEscapes = interpretEscapes
        self.hidePreview = hidePreview
        self.isProtected = isProtected
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, text, kind, aliases, tags, isFavorite, interpretEscapes
        case hidePreview, isProtected, allowedBundleIdentifiers, createdAt, updatedAt, lastUsedAt, useCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        // Existing libraries contain only text records and have no kind field.
        kind = try values.decodeIfPresent(RecordKind.self, forKey: .kind) ?? .text
        aliases = try values.decode([String].self, forKey: .aliases)
        tags = try values.decode([String].self, forKey: .tags)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        interpretEscapes = try values.decode(Bool.self, forKey: .interpretEscapes)
        hidePreview = try values.decode(Bool.self, forKey: .hidePreview)
        isProtected = try values.decode(Bool.self, forKey: .isProtected)
        allowedBundleIdentifiers = try values.decode([String].self, forKey: .allowedBundleIdentifiers)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try values.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount = try values.decode(Int.self, forKey: .useCount)
    }
}

struct RecordDraft: Identifiable, Equatable {
    var id: UUID
    var name: String
    var text: String
    var kind: RecordKind
    var aliasesText: String
    var tagsText: String
    var isFavorite: Bool
    var interpretEscapes: Bool
    var hidePreview: Bool
    var isProtected: Bool
    var allowedAppsText: String
    var originalRecord: TextRecord?

    init(record: TextRecord? = nil, resolvedText: String = "") {
        id = record?.id ?? UUID()
        name = record?.name ?? ""
        text = record == nil ? "" : resolvedText
        kind = record?.kind ?? .text
        aliasesText = record?.aliases.joined(separator: ", ") ?? ""
        tagsText = record?.tags.joined(separator: ", ") ?? ""
        isFavorite = record?.isFavorite ?? false
        interpretEscapes = record?.interpretEscapes ?? false
        hidePreview = record?.hidePreview ?? false
        isProtected = record?.isProtected ?? false
        allowedAppsText = record?.allowedBundleIdentifiers.joined(separator: ", ") ?? ""
        originalRecord = record
    }

    private func components(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func makeRecord(now: Date = Date()) -> TextRecord {
        var record = originalRecord ?? TextRecord(id: id, name: name, text: text)
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.text = isProtected ? nil : text
        record.kind = kind
        record.aliases = components(from: aliasesText)
        record.tags = components(from: tagsText)
        record.isFavorite = isFavorite
        record.interpretEscapes = kind == .text && interpretEscapes
        record.hidePreview = hidePreview || isProtected
        record.isProtected = isProtected
        record.allowedBundleIdentifiers = kind == .text ? components(from: allowedAppsText) : []
        record.updatedAt = now
        return record
    }
}
