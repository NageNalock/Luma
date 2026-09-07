import Foundation

struct GitHubReleasePage: Sendable {
    let tagName: String
    let title: String
    let pageURL: URL
    let version: AppVersion
    let isPrerelease: Bool

    var assetsURL: URL {
        GitHubReleasePageParser.releasesURL
            .appendingPathComponent("expanded_assets")
            .appendingPathComponent(tagName)
    }
}

enum GitHubReleasePageParser {
    static let releasesURL = URL(string: "https://github.com/NageNalock/Luma/releases")!

    static func releases(from data: Data) throws -> [GitHubReleasePage] {
        let document = try htmlDocument(from: data)
        // Read release headings, excluding links to other versions in release notes.
        let links = try document.nodes(forXPath:
            "//a[contains(concat(' ', normalize-space(@class), ' '), ' Link--primary ')]"
        )
        var seen = Set<String>()
        var releases: [GitHubReleasePage] = []
        let tagRoot = releasesURL.appendingPathComponent("tag").pathComponents

        for case let link as XMLElement in links {
            guard let href = link.attribute(forName: "href")?.stringValue,
                  let url = repositoryURL(from: href),
                  Array(url.pathComponents.dropLast()) == tagRoot else { continue }
            let tag = url.lastPathComponent
            guard !tag.contains("/"),
                  let version = AppVersion(releaseTag: tag),
                  seen.insert(tag).inserted else { continue }

            let labels = try link.nodes(forXPath:
                "ancestor::div[contains(concat(' ', normalize-space(@class), ' '), ' Box-body ')][1]" +
                "//span[contains(concat(' ', normalize-space(@class), ' '), ' Label ')]"
            ).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !labels.contains("Draft") else { continue }

            let title = link.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            releases.append(GitHubReleasePage(
                tagName: tag,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? tag,
                pageURL: url,
                version: version,
                isPrerelease: labels.contains("Pre-release")
            ))
        }
        return releases.sorted { $0.version > $1.version }
    }

    static func release(_ page: GitHubReleasePage, assets data: Data) throws -> AppRelease? {
        let document = try htmlDocument(from: data)
        let links = try document.nodes(forXPath: "//a/@href")
        let downloadRoot = releasesURL
            .appendingPathComponent("download")
            .appendingPathComponent(page.tagName)
            .pathComponents
        var assets: [String: URL] = [:]

        for link in links {
            guard let href = link.stringValue,
                  let url = repositoryURL(from: href),
                  Array(url.pathComponents.dropLast()) == downloadRoot,
                  !url.lastPathComponent.contains("/") else { continue }
            assets[url.lastPathComponent] = url
        }

        // Only offer a DMG when the same release contains its matching checksum file.
        for name in assets.keys.sorted() where name.hasSuffix(".dmg") {
            guard let dmgURL = assets[name],
                  let checksumURL = assets["\(name).sha256"] else { continue }
            return AppRelease(
                tagName: page.tagName,
                title: page.title,
                pageURL: page.pageURL,
                version: page.version,
                isPrerelease: page.isPrerelease,
                dmgName: name,
                dmgURL: dmgURL,
                checksumURL: checksumURL
            )
        }
        return nil
    }

    private static func htmlDocument(from data: Data) throws -> XMLDocument {
        guard let html = String(data: data, encoding: .utf8) else {
            throw GitHubUpdateError.invalidResponse
        }
        do {
            // The string initializer preserves UTF-8 even when libxml ignores HTML5's meta charset.
            return try XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        } catch {
            throw GitHubUpdateError.invalidResponse
        }
    }

    private static func repositoryURL(from href: String) -> URL? {
        guard let url = URL(string: href, relativeTo: releasesURL)?.absoluteURL,
              url.scheme == "https", url.host == "github.com",
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.hasPrefix(releasesURL.path + "/") else { return nil }
        return url
    }
}
