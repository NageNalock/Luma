import Foundation

struct TextDiffHunk: Sendable {
    let leftRange: NSRange
    let rightRange: NSRange
    let leftLines: Range<Int>
    let rightLines: Range<Int>
    let removedRanges: [NSRange]
    let insertedRanges: [NSRange]
}

struct TextDiffResult: Sendable {
    var hunks: [TextDiffHunk] = []
    var usesCoarseComparison = false

    var removedLineCount: Int { hunks.reduce(0) { $0 + $1.leftLines.count } }
    var insertedLineCount: Int { hunks.reduce(0) { $0 + $1.rightLines.count } }

    func destination(from current: Int?, offset: Int) -> Int? {
        guard !hunks.isEmpty else { return nil }
        guard let current, hunks.indices.contains(current) else {
            return offset < 0 ? hunks.count - 1 : 0
        }
        return ((current + offset) % hunks.count + hunks.count) % hunks.count
    }
}

enum TextDiffer {
    private struct Line {
        let text: String
        let range: NSRange
    }

    private struct ChangedBlock {
        let left: Range<Int>
        let right: Range<Int>
    }

    /// Compare exact text, including whitespace, line endings and Unicode encoding.
    /// Trimming shared edges keeps small edits in large documents inexpensive.
    static func compare(_ left: String, _ right: String) -> TextDiffResult {
        guard !left.utf16.elementsEqual(right.utf16) else { return TextDiffResult() }
        let leftLines = lines(in: left)
        let rightLines = lines(in: right)
        var coarse = false
        let blocks = changedBlocks(
            leftLines, rightLines,
            budget: 4_000_000,
            coarse: &coarse,
            key: { Array($0.text.utf16) },
            equal: { $0.text.utf16.elementsEqual($1.text.utf16) }
        )
        var result = TextDiffResult(usesCoarseComparison: coarse)

        for block in blocks {
            guard !Task<Never, Never>.isCancelled else { return TextDiffResult() }
            let leftRange = textRange(for: block.left, lines: leftLines, length: left.utf16.count)
            let rightRange = textRange(for: block.right, lines: rightLines, length: right.utf16.count)
            let leftText = (left as NSString).substring(with: leftRange)
            let rightText = (right as NSString).substring(with: rightRange)
            let leftCharacters = Array(leftText)
            let rightCharacters = Array(rightText)
            var inlineCoarse = false
            let inlineBlocks = changedBlocks(
                leftCharacters, rightCharacters,
                budget: 1_000_000,
                coarse: &inlineCoarse,
                key: { Array($0.utf16) },
                equal: { String($0).utf16.elementsEqual(String($1).utf16) }
            )
            let leftOffsets = offsets(for: leftCharacters, startingAt: leftRange.location)
            let rightOffsets = offsets(for: rightCharacters, startingAt: rightRange.location)
            result.usesCoarseComparison = result.usesCoarseComparison || inlineCoarse
            result.hunks.append(TextDiffHunk(
                leftRange: leftRange,
                rightRange: rightRange,
                leftLines: block.left,
                rightLines: block.right,
                removedRanges: inlineBlocks.compactMap { range($0.left, offsets: leftOffsets) },
                insertedRanges: inlineBlocks.compactMap { range($0.right, offsets: rightOffsets) }
            ))
        }
        return result
    }

    private static func changedBlocks<Element>(
        _ left: [Element], _ right: [Element],
        budget: Int,
        coarse: inout Bool,
        key: (Element) -> [UInt16],
        equal: (Element, Element) -> Bool
    ) -> [ChangedBlock] {
        var start = 0
        while start < min(left.count, right.count), equal(left[start], right[start]) {
            start += 1
        }
        var leftEnd = left.count
        var rightEnd = right.count
        while leftEnd > start, rightEnd > start, equal(left[leftEnd - 1], right[rightEnd - 1]) {
            leftEnd -= 1
            rightEnd -= 1
        }
        guard leftEnd > start || rightEnd > start else { return [] }
        guard leftEnd > start, rightEnd > start else {
            return [ChangedBlock(left: start..<leftEnd, right: start..<rightEnd)]
        }

        // Bound worst-case work on unrelated input; retain exact input ranges even
        // when a very large replacement has to be highlighted as one block.
        guard leftEnd - start <= budget / (rightEnd - start) else {
            // Unique shared lines split long documents into small independent edits.
            // A longest increasing subsequence keeps anchors in document order.
            let anchors = sharedAnchors(left, start..<leftEnd, right, start..<rightEnd, key: key)
            if !anchors.isEmpty {
                var result: [ChangedBlock] = []
                var leftStart = start
                var rightStart = start
                for (leftAnchor, rightAnchor) in anchors + [(leftEnd, rightEnd)] {
                    let pieces = changedBlocks(
                        Array(left[leftStart..<leftAnchor]), Array(right[rightStart..<rightAnchor]),
                        budget: budget, coarse: &coarse, key: key, equal: equal
                    )
                    result += pieces.map {
                        ChangedBlock(
                            left: ($0.left.lowerBound + leftStart)..<($0.left.upperBound + leftStart),
                            right: ($0.right.lowerBound + rightStart)..<($0.right.upperBound + rightStart)
                        )
                    }
                    leftStart = leftAnchor + 1
                    rightStart = rightAnchor + 1
                }
                return result
            }
            coarse = true
            return [ChangedBlock(left: start..<leftEnd, right: start..<rightEnd)]
        }
        let changes = right[start..<rightEnd].difference(from: left[start..<leftEnd], by: equal)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(start + offset)
            case .insert(let offset, _, _): inserted.insert(start + offset)
            }
        }

        var blocks: [ChangedBlock] = []
        var leftIndex = start
        var rightIndex = start
        while leftIndex < leftEnd || rightIndex < rightEnd {
            let leftStart = leftIndex
            let rightStart = rightIndex
            while leftIndex < leftEnd, removed.contains(leftIndex) { leftIndex += 1 }
            while rightIndex < rightEnd, inserted.contains(rightIndex) { rightIndex += 1 }
            if leftIndex != leftStart || rightIndex != rightStart {
                blocks.append(ChangedBlock(left: leftStart..<leftIndex, right: rightStart..<rightIndex))
            } else {
                leftIndex += 1
                rightIndex += 1
            }
        }
        return blocks
    }

    private static func sharedAnchors<Element>(
        _ left: [Element], _ leftRange: Range<Int>,
        _ right: [Element], _ rightRange: Range<Int>,
        key: (Element) -> [UInt16]
    ) -> [(Int, Int)] {
        var leftPositions: [[UInt16]: Int] = [:]
        var rightPositions: [[UInt16]: Int] = [:]
        for index in leftRange {
            let value = key(left[index])
            leftPositions[value] = leftPositions[value] == nil ? index : -1
        }
        for index in rightRange {
            let value = key(right[index])
            rightPositions[value] = rightPositions[value] == nil ? index : -1
        }
        let pairs = leftPositions.compactMap { value, index -> (Int, Int)? in
            guard index >= 0, let other = rightPositions[value], other >= 0 else { return nil }
            return (index, other)
        }.sorted { $0.0 < $1.0 }
        var tails: [Int] = []
        var previous = Array(repeating: -1, count: pairs.count)
        for index in pairs.indices {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if pairs[tails[middle]].1 < pairs[index].1 { low = middle + 1 }
                else { high = middle }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) }
            else { tails[low] = index }
        }
        var anchors: [(Int, Int)] = []
        var index = tails.last ?? -1
        while index >= 0 {
            anchors.append(pairs[index])
            index = previous[index]
        }
        return anchors.reversed()
    }

    private static func lines(in text: String) -> [Line] {
        let units = Array(text.utf16)
        let source = text as NSString
        var result: [Line] = []
        var start = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            index += 1
            if unit == 13, index < units.count, units[index] == 10 { index += 1 }
            if unit == 10 || unit == 13 || unit == 0x2028 || unit == 0x2029 {
                let range = NSRange(location: start, length: index - start)
                result.append(Line(text: source.substring(with: range), range: range))
                start = index
            }
        }
        if start < units.count {
            let range = NSRange(location: start, length: units.count - start)
            result.append(Line(text: source.substring(with: range), range: range))
        }
        return result
    }

    private static func textRange(for indices: Range<Int>, lines: [Line], length: Int) -> NSRange {
        let start = indices.lowerBound < lines.count ? lines[indices.lowerBound].range.location : length
        let end = indices.isEmpty ? start : NSMaxRange(lines[indices.upperBound - 1].range)
        return NSRange(location: start, length: end - start)
    }

    private static func offsets(for characters: [Character], startingAt start: Int) -> [Int] {
        var result = [start]
        for character in characters { result.append(result.last! + character.utf16.count) }
        return result
    }

    private static func range(_ indices: Range<Int>, offsets: [Int]) -> NSRange? {
        guard !indices.isEmpty else { return nil }
        return NSRange(location: offsets[indices.lowerBound], length: offsets[indices.upperBound] - offsets[indices.lowerBound])
    }
}
