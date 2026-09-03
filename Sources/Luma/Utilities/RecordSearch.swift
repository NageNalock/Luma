import Foundation

enum RecordSearch {
    static func results(for query: String, in records: [TextRecord]) -> [TextRecord] {
        let normalizedQuery = normalize(query)

        if normalizedQuery.isEmpty {
            return records.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                if $0.lastUsedAt != $1.lastUsedAt {
                    return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
                }
                if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        return records.compactMap { record -> (TextRecord, Int)? in
            let searchable = [record.name] + record.aliases + record.tags
            let best = searchable.map { score(normalizedQuery, against: normalize($0)) }.max() ?? 0
            return best > 0 ? (record, best) : nil
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.isFavorite != $1.0.isFavorite { return $0.0.isFavorite }
            return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
        }
        .map(\.0)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func score(_ needle: String, against haystack: String) -> Int {
        guard !needle.isEmpty, !haystack.isEmpty else { return 0 }
        if haystack == needle { return 1_000 }
        if haystack.hasPrefix(needle) { return 800 - max(0, haystack.count - needle.count) }
        if let range = haystack.range(of: needle) {
            return 600 - haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        }

        var cursor = haystack.startIndex
        var matched = 0
        var gaps = 0
        for character in needle {
            guard let match = haystack[cursor...].firstIndex(of: character) else { return 0 }
            gaps += haystack.distance(from: cursor, to: match)
            matched += 1
            cursor = haystack.index(after: match)
        }

        return matched == needle.count ? max(1, 300 - gaps) : 0
    }
}
