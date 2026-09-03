import Foundation

struct TextRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var text: String?
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
}

struct RecordDraft: Identifiable, Equatable {
    var id: UUID
    var name: String
    var text: String
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
        record.aliases = components(from: aliasesText)
        record.tags = components(from: tagsText)
        record.isFavorite = isFavorite
        record.interpretEscapes = interpretEscapes
        record.hidePreview = hidePreview || isProtected
        record.isProtected = isProtected
        record.allowedBundleIdentifiers = components(from: allowedAppsText)
        record.updatedAt = now
        return record
    }
}
