import Foundation

enum TextDiffSelfTests {
    static func run(check: (String, Bool) -> Void) {
        check("diff empty input", TextDiffer.compare("", "").hunks.isEmpty)
        check("diff identical Unicode text", TextDiffer.compare("你好 👩🏽‍💻\r\n", "你好 👩🏽‍💻\r\n").hunks.isEmpty)

        let added = TextDiffer.compare("", "hello\n世界👩🏽‍💻\n")
        check("diff entirely added text", added.hunks.count == 1 && added.removedLineCount == 0 && added.insertedLineCount == 2)
        check("diff empty-side anchor", added.hunks.first?.leftRange == NSRange(location: 0, length: 0))
        let deleted = TextDiffer.compare("hello\n世界👩🏽‍💻\n", "")
        check("diff entirely deleted text", deleted.hunks.count == 1 && deleted.removedLineCount == 2 && deleted.insertedLineCount == 0)

        let replacement = TextDiffer.compare("alpha\nbravo\ncharlie", "alpha\nBRAVO\ncharlie")
        check("diff replacement line", replacement.hunks.count == 1 && replacement.hunks.first?.leftLines == 1..<2)
        check("diff highlights only changed characters", replacement.hunks.first?.removedRanges == [NSRange(location: 6, length: 5)])
        check("diff adjacent edits form one hunk", TextDiffer.compare("a\nb\nc\nd", "a\nB\nC\nd").hunks.count == 1)

        let separated = TextDiffer.compare("a\nkeep\nb\nkeep\nc", "A\nkeep\nB\nkeep\nC")
        check("diff separates edits around unchanged lines", separated.hunks.count == 3)
        check("diff next begins at first hunk", separated.destination(from: nil, offset: 1) == 0)
        check("diff previous begins at last hunk", separated.destination(from: nil, offset: -1) == 2)
        check("diff navigates forward", separated.destination(from: 0, offset: 1) == 1)
        check("diff next wraps to first", separated.destination(from: 2, offset: 1) == 0)
        check("diff previous wraps to last", separated.destination(from: 0, offset: -1) == 2)
        check("diff one hunk remains navigable", replacement.destination(from: 0, offset: 1) == 0)
        check("diff identical input has no navigation target", TextDiffResult().destination(from: 0, offset: 1) == nil)
        check("diff stale selection resets safely", separated.destination(from: 99, offset: 1) == 0)

        let newline = TextDiffer.compare("hello", "hello\n")
        check("diff detects final newline", newline.hunks.count == 1 && newline.hunks.first?.insertedRanges == [NSRange(location: 5, length: 1)])
        let space = TextDiffer.compare("a b\t", "a  b\t")
        check("diff preserves whitespace changes", space.hunks.first?.insertedRanges == [NSRange(location: 2, length: 1)])
        let emoji = TextDiffer.compare("你好👩🏽‍💻！", "你好🧑‍🚀！")
        check("diff keeps emoji graphemes intact", emoji.hunks.first?.removedRanges == [NSRange(location: 2, length: "👩🏽‍💻".utf16.count)])
        check("diff detects Unicode normalization changes", !TextDiffer.compare("é", "e\u{301}").hunks.isEmpty)

        let fixtures = [
            ("a\na\nb\na\n", "a\nb\na\na\n"),
            ("a\nb\n", "a\n\nb\n"),
            ("a\r\nb\r\n", "a\nb\n"),
            ("a\rb", "a\rb\r"),
            ("a\u{2028}b", "a\u{2028}B"),
            ("first\nlast", "new\nfirst\nlast\nend"),
            ("one\ntwo\nthree", "three\none\ntwo"),
            ("你好👩🏽‍💻！", "你好🧑‍🚀！"),
            ("é", "e\u{301}"),
            ("", "\n"), ("\n", ""),
            ("a\nb", "ab"),
            (String(repeating: "x", count: 10_000) + "old", String(repeating: "x", count: 10_000) + "new")
        ]
        for (index, fixture) in fixtures.enumerated() {
            check("diff fixture \(index) reconstructs exact target", reconstructs(fixture.0, fixture.1))
        }

        let longLines = (0..<5_000).map { "line \($0)\n" }
        var modifiedLines = longLines
        modifiedLines[3] = "changed near start\n"
        modifiedLines[4_900] = "changed near end\n"
        let longResult = TextDiffer.compare(longLines.joined(), modifiedLines.joined())
        check("diff long document retains separate edits", longResult.hunks.count == 2 && !longResult.usesCoarseComparison)
        check("diff long document ranges reconstruct target", reconstructs(longLines.joined(), modifiedLines.joined()))
        let unrelatedLeft = String(repeating: "a\n", count: 4_000)
        let unrelatedRight = String(repeating: "b\n", count: 4_000)
        check("diff bounds large unrelated input", TextDiffer.compare(unrelatedLeft, unrelatedRight).usesCoarseComparison)
        check("diff coarse ranges reconstruct exact target", reconstructs(unrelatedLeft, unrelatedRight))

        // Deterministic mixed edits exercise repeated lines and empty-side hunks.
        var seed: UInt64 = 0x4C554D41
        func next(_ count: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(count))
        }
        let tokens = ["a\n", "b\n", "\n", "中文\n", "👩🏽‍💻\n", "\t \n"]
        for index in 0..<160 {
            let left = (0..<next(16)).map { _ in tokens[next(tokens.count)] }
            var right = left
            for _ in 0..<(1 + next(6)) {
                switch next(3) {
                case 0: right.insert(tokens[next(tokens.count)], at: next(right.count + 1))
                case 1 where !right.isEmpty: right.remove(at: next(right.count))
                case 2 where !right.isEmpty: right[next(right.count)] = tokens[next(tokens.count)]
                default: break
                }
            }
            check("diff mixed edits \(index) preserve exact text", reconstructs(left.joined(), right.joined()))
        }
    }

    private static func reconstructs(_ left: String, _ right: String) -> Bool {
        let result = TextDiffer.compare(left, right)
        let rebuilt = NSMutableString(string: left)
        let unchangedLeft = NSMutableString(string: left)
        let unchangedRight = NSMutableString(string: right)
        for hunk in result.hunks.reversed() {
            guard NSMaxRange(hunk.leftRange) <= (left as NSString).length,
                  NSMaxRange(hunk.rightRange) <= (right as NSString).length else { return false }
            rebuilt.replaceCharacters(in: hunk.leftRange, with: (right as NSString).substring(with: hunk.rightRange))
            for range in hunk.removedRanges.reversed() { unchangedLeft.deleteCharacters(in: range) }
            for range in hunk.insertedRanges.reversed() { unchangedRight.deleteCharacters(in: range) }
        }
        return (rebuilt as String).utf16.elementsEqual(right.utf16)
            && (unchangedLeft as String).utf16.elementsEqual((unchangedRight as String).utf16)
    }
}
