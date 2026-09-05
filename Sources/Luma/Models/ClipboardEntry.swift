import Foundation

struct ClipboardEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    var copiedAt: Date
    var sourceAppName: String?
    var sourceBundleIdentifier: String?

    init(
        id: UUID = UUID(),
        text: String,
        copiedAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    var preview: String {
        text
            .replacingOccurrences(of: "\r\n", with: " ↵ ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
    }
}
