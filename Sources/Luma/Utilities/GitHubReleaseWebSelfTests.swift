import Foundation

enum GitHubReleaseWebSelfTests {
    static func run(check: (String, Bool) -> Void) {
        do {
            let pages = try GitHubReleasePageParser.releases(from: html("""
            <section><div class="Box-body">
              <a class="Link--primary Link" href="/NageNalock/Luma/releases/tag/v0.1.0">Stable</a>
              <span class="Label Label--success">Latest</span>
            </div></section>
            <section><div class="Box-body p-3">
              <div><a class="Link--primary Link" href="/NageNalock/Luma/releases/tag/v0.2.0-build.9.1-abc">Build 9</a></div>
              <span class="Label">Pre-release</span>
              <a href="/NageNalock/Luma/releases/tag/v99.0.0">A version mentioned in notes</a>
            </div></section>
            <section><div class="Box-body">
              <a class="Link Link--primary" href="https://github.com/NageNalock/Luma/releases/tag/v0.2.0-build.10.1-def">Luma &amp; 工具</a>
              <span class="Label Label--warning"> Pre-release </span>
              <a class="Link--primary" href="/NageNalock/Luma/releases/tag/v0.2.0-build.10.1-def">Duplicate</a>
            </div></section>
            <section><div class="Box-body">
              <a class="Link--primary" href="/NageNalock/Luma/releases/tag/v100.0.0">Unpublished</a>
              <span class="Label">Draft</span>
            </div></section>
            <a class="Link--primary" href="/NageNalock/Luma/releases/tag/not-a-version">Invalid version</a>
            <a class="Link--primary" href="/another/repository/releases/tag/v101.0.0">Another repository</a>
            <a class="Link--primary" href="https://example.com/NageNalock/Luma/releases/tag/v102.0.0">Another host</a>
            """))
            check("release web filters notes, duplicates, drafts and unrelated links", pages.count == 3)
            check("release web sorts versions numerically", pages.map(\.tagName) == [
                "v0.2.0-build.10.1-def", "v0.2.0-build.9.1-abc", "v0.1.0"
            ])
            check("release web decodes title entities and Unicode", pages.first?.title == "Luma & 工具")
            check("release web retains prereleases", pages.prefix(2).allSatisfy(\.isPrerelease))
            check("release web keeps badges scoped to their release", pages.last?.isPrerelease == false)

            guard let page = pages.first else { return }
            let root = "/NageNalock/Luma/releases/download/\(page.tagName)/"
            let release = try GitHubReleasePageParser.release(page, assets: html("""
            <ul>
              <li><a href="\(root)A-incomplete.dmg">Incomplete upload</a></li>
              <li><a href="\(root)Luma.dmg">Luma.dmg</a></li>
              <li><a href="https://github.com\(root)Luma.dmg.sha256">Luma.dmg.sha256</a></li>
              <li><a href="/NageNalock/Luma/archive/refs/tags/\(page.tagName).zip">Source code</a></li>
            </ul>
            """))
            check("release web requires a matching DMG and checksum pair", release?.dmgName == "Luma.dmg")
            check("release web resolves relative asset URLs", release?.dmgURL.absoluteString == "https://github.com\(root)Luma.dmg")
            check("release web preserves version metadata", release?.version == page.version && release?.isPrerelease == true)
            check("release web constructs public asset list URL", page.assetsURL.absoluteString ==
                "https://github.com/NageNalock/Luma/releases/expanded_assets/\(page.tagName)")

            let rejectedChecksums = [
                "\(root)Different.dmg.sha256",
                "/NageNalock/Luma/releases/download/v0.1.0/Luma.dmg.sha256",
                "/another/repository/releases/download/\(page.tagName)/Luma.dmg.sha256",
                "https://example.com\(root)Luma.dmg.sha256",
                "http://github.com\(root)Luma.dmg.sha256",
                "https://user@github.com\(root)Luma.dmg.sha256",
                "https://github.com:8443\(root)Luma.dmg.sha256",
                "\(root)Luma.dmg.sha256?other=true",
                "\(root)nested%2FLuma.dmg.sha256"
            ]
            for (index, checksum) in rejectedChecksums.enumerated() {
                let incomplete = try GitHubReleasePageParser.release(page, assets: html("""
                <a href="\(root)Luma.dmg">DMG</a><a href="\(checksum)">Checksum</a>
                """))
                check("release web rejects unrelated or invalid checksum URL \(index)", incomplete == nil)
            }

            check("release web rejects missing assets", try GitHubReleasePageParser.release(page, assets: html("<p>No assets</p>")) == nil)
            check("release web handles empty listing", try GitHubReleasePageParser.releases(from: html("<p>No releases</p>")).isEmpty)
        } catch {
            check("release web parsing: \(error.localizedDescription)", false)
        }
    }

    private static func html(_ body: String) -> Data {
        Data("<html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>".utf8)
    }
}
