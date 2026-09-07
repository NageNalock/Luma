import CryptoKit
import Foundation

struct AppVersion: Comparable, Sendable {
    let components: [Int]
    let build: Int
    let attempt: Int

    init?(versionString: String, buildString: String, attempt: Int = 0) {
        let parsedComponents = versionString.split(separator: ".").compactMap { Int($0) }
        guard parsedComponents.count == versionString.split(separator: ".").count,
              (2...3).contains(parsedComponents.count) else {
            return nil
        }

        let buildParts = buildString.split(separator: ".").compactMap { Int($0) }
        guard !buildParts.isEmpty else { return nil }

        components = parsedComponents + Array(repeating: 0, count: 3 - parsedComponents.count)
        build = buildParts[0]
        self.attempt = buildParts.count > 1 ? buildParts[1] : attempt
    }

    init?(releaseTag: String) {
        let normalizedTag = releaseTag.hasPrefix("v") ? String(releaseTag.dropFirst()) : releaseTag
        let versionString: String
        let buildString: String

        if let buildMarker = normalizedTag.range(of: "-build.") {
            versionString = String(normalizedTag[..<buildMarker.lowerBound])
            let buildSuffix = normalizedTag[buildMarker.upperBound...]
            buildString = String(buildSuffix.split(separator: "-", maxSplits: 1).first ?? "")
        } else {
            versionString = normalizedTag
            buildString = "0"
        }
        self.init(versionString: versionString, buildString: buildString)
    }

    static var current: AppVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return AppVersion(versionString: version, buildString: build)
            ?? AppVersion(versionString: "0.1.0", buildString: "0")!
    }

    var displayString: String {
        let version = components.map(String.init).joined(separator: ".")
        guard build > 0 || attempt > 0 else { return version }
        let buildSuffix = attempt > 0 ? "\(build).\(attempt)" : String(build)
        return "\(version)（构建 \(buildSuffix)）"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.components != rhs.components {
            return lhs.components.lexicographicallyPrecedes(rhs.components)
        }
        if lhs.build != rhs.build { return lhs.build < rhs.build }
        return lhs.attempt < rhs.attempt
    }
}

struct AppRelease: Identifiable, Sendable {
    let tagName: String
    let title: String
    let pageURL: URL
    let version: AppVersion
    let isPrerelease: Bool
    let dmgName: String
    let dmgURL: URL
    let checksumURL: URL

    var id: String { tagName }
}

enum GitHubUpdateError: LocalizedError {
    case invalidResponse
    case requestFailed(Int)
    case noDownloadableRelease
    case invalidAssetURL
    case invalidChecksum
    case checksumMismatch
    case cannotOpenDownload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub 返回了无法识别的响应。"
        case .requestFailed(let statusCode):
            if statusCode == 403 || statusCode == 429 {
                return "GitHub 暂时拒绝了网页请求（HTTP \(statusCode)），请稍后重试。"
            }
            return "GitHub 请求失败（HTTP \(statusCode)）。"
        case .noDownloadableRelease:
            return "GitHub Release 中没有可用的 Luma DMG。"
        case .invalidAssetURL:
            return "Release 下载地址无效。"
        case .invalidChecksum:
            return "Release 的 SHA-256 校验文件无效。"
        case .checksumMismatch:
            return "下载文件校验失败，已拒绝打开。"
        case .cannotOpenDownload:
            return "安装镜像已下载，但系统无法打开它。"
        }
    }
}

actor GitHubUpdateService {
    private let session: URLSession
    private var cachedRelease: (release: AppRelease, expiresAt: Date)?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func newestRelease() async throws -> AppRelease {
        if let cachedRelease, cachedRelease.expiresAt > Date() {
            return cachedRelease.release
        }

        let data = try await fetchPage(GitHubReleasePageParser.releasesURL)
        let releases = try GitHubReleasePageParser.releases(from: data)
        for page in releases {
            let assets: Data
            do {
                assets = try await fetchPage(page.assetsURL)
            } catch GitHubUpdateError.requestFailed(404) {
                // A release can disappear between loading the list and its assets.
                continue
            }
            if let release = try GitHubReleasePageParser.release(page, assets: assets) {
                cachedRelease = (release, Date().addingTimeInterval(60))
                return release
            }
        }
        throw GitHubUpdateError.noDownloadableRelease
    }

    func download(_ release: AppRelease) async throws -> URL {
        let checksumRequest = try makeRequest(for: release.checksumURL)
        let (checksumData, checksumResponse) = try await session.data(for: checksumRequest)
        try validate(checksumResponse)
        guard let expectedChecksum = Self.parseChecksum(checksumData) else {
            throw GitHubUpdateError.invalidChecksum
        }

        let downloadRequest = try makeRequest(for: release.dmgURL)
        let (temporaryURL, downloadResponse) = try await session.download(for: downloadRequest)
        try validate(downloadResponse)

        let actualChecksum = try Self.sha256(of: temporaryURL)
        guard actualChecksum.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
            throw GitHubUpdateError.checksumMismatch
        }

        let fileManager = FileManager.default
        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let updateDirectory = cacheRoot
            .appendingPathComponent("com.luma.app", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)

        let safeName = URL(fileURLWithPath: release.dmgName).lastPathComponent
        guard safeName == release.dmgName, safeName.hasSuffix(".dmg") else {
            throw GitHubUpdateError.invalidAssetURL
        }

        let destination = updateDirectory.appendingPathComponent(safeName, isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    nonisolated static func parseChecksum(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let token = text.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }
        let checksum = String(token)
        guard checksum.count == 64, checksum.allSatisfy(\.isHexDigit) else { return nil }
        return checksum.lowercased()
    }

    private func fetchPage(_ url: URL) async throws -> Data {
        let request = try makeRequest(for: url, accept: "text/html")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    private func makeRequest(for url: URL, accept: String = "application/octet-stream") throws -> URLRequest {
        guard url.scheme == "https",
              url.host == "github.com",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else {
            throw GitHubUpdateError.invalidAssetURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let version = AppVersion.current.components.map(String.init).joined(separator: ".")
        request.setValue("Luma/\(version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubUpdateError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubUpdateError.requestFailed(httpResponse.statusCode)
        }
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
