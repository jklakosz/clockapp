import Foundation
import AppKit

/// Self-updater backed by GitHub Releases (public repo, anonymous API).
///
/// Security: before installing, the downloaded app MUST satisfy the pinned codesign
/// requirement below (bundle id + our exact signing certificate). A compromised host
/// or MITM therefore cannot ship us a foreign binary — installs fail closed.
enum UpdaterService {
    static let owner = "jklakosz"
    static let repo = "clockapp"

    /// Designated requirement pinned to the "Clockapp Dev" certificate.
    /// If that cert is ever regenerated, bump this hash and ship one manual update.
    private static let pinnedRequirement =
        #"identifier "com.jules.clockapp" and certificate leaf = H"e0c2110b5834b00bf1c408d7b95765486ee08d38""#

    struct Release {
        let version: String
        let zipURL: URL
    }

    /// Current app version from the bundle (nil when run as a bare executable).
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Check

    /// Returns the newest applicable release if it is strictly newer than the running
    /// version. With `allowPrereleases`, release candidates are considered too;
    /// otherwise only stable releases (GitHub's `releases/latest` excludes prereleases).
    static func checkForUpdate(allowPrereleases: Bool) async throws -> Release? {
        guard let current = currentVersion else { return nil }
        let best = try await (allowPrereleases ? newestPrerelease() : latestStable())
        return makeRelease(best, newerThan: current)
    }

    private static func latestStable() async throws -> ReleaseDTO? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        let (data, response) = try await get(url)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.network }
        if http.statusCode == 404 { return nil } // no stable release yet
        guard http.statusCode == 200 else { throw UpdateError.network }
        return try JSONDecoder().decode(ReleaseDTO.self, from: data)
    }

    /// Highest-versioned non-draft release across the recent list (prereleases included).
    private static func newestPrerelease() async throws -> ReleaseDTO? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")!
        let (data, response) = try await get(url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.network }
        let all = try JSONDecoder().decode([ReleaseDTO].self, from: data)
        return all.filter { !$0.draft }
            .max { SemVer(cleanTag($0.tagName)) < SemVer(cleanTag($1.tagName)) }
    }

    private static func makeRelease(_ dto: ReleaseDTO?, newerThan current: String) -> Release? {
        guard let dto else { return nil }
        let version = cleanTag(dto.tagName)
        guard SemVer(version) > SemVer(current),
              let asset = dto.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let zipURL = URL(string: asset.browserDownloadUrl) else {
            return nil
        }
        return Release(version: version, zipURL: zipURL)
    }

    private static func cleanTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private static func get(_ url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: req)
    }

    // MARK: - Install

    /// Downloads, verifies and swaps the app bundle in place.
    /// Returns the path of the installed app; the caller relaunches.
    static func downloadAndInstall(_ release: Release) async throws -> URL {
        let targetURL = Bundle.main.bundleURL
        guard targetURL.pathExtension == "app" else { throw UpdateError.notABundle }

        // 1. Download the zip.
        let (tmpZip, _) = try await URLSession.shared.download(from: release.zipURL)

        // 2. Unzip into a scratch dir.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clockapp-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        try run("/usr/bin/ditto", "-xk", tmpZip.path, workDir.path)

        // 3. Locate the .app inside.
        guard let newApp = try FileManager.default
            .contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.badArchive
        }

        // 4. Strip quarantine, then enforce the pinned signature. Order matters:
        //    verification runs on the exact bits we are about to install.
        try? run("/usr/bin/xattr", "-cr", newApp.path)
        do {
            try run("/usr/bin/codesign", "--verify", "--deep", "--strict",
                    "-R=" + pinnedRequirement, newApp.path)
        } catch {
            throw UpdateError.signatureMismatch
        }

        // 5. Swap: move the running bundle aside, move the new one in, roll back on failure.
        let backup = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clockapp-backup-\(UUID().uuidString).app")
        try FileManager.default.moveItem(at: targetURL, to: backup)
        do {
            try FileManager.default.moveItem(at: newApp, to: targetURL)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: targetURL) // roll back
            throw UpdateError.installFailed
        }
        try? FileManager.default.removeItem(at: backup)
        return targetURL
    }

    /// Relaunches the (new) app and terminates this instance.
    @MainActor
    static func relaunch(_ appURL: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; /usr/bin/open \"\(appURL.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func run(_ launchPath: String, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.toolFailed(launchPath) }
    }

    private struct ReleaseDTO: Decodable {
        let tagName: String
        let assets: [Asset]
        let draft: Bool
        let prerelease: Bool
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets, draft, prerelease
        }
    }
}

/// Minimal semantic-version compare: numeric core plus optional prerelease suffix
/// ("0.4.0-rc.2"). A stable version outranks its prereleases (0.4.0 > 0.4.0-rc.2),
/// and prereleases order by their identifiers (rc.1 < rc.2 < rc.10).
struct SemVer: Comparable {
    let core: [Int]
    let pre: [String]

    init(_ raw: String) {
        var s = raw
        if s.hasPrefix("v") { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        core = (parts.first.map(String.init) ?? "0").split(separator: ".").map { Int($0) ?? 0 }
        pre = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    static func < (a: SemVer, b: SemVer) -> Bool {
        for i in 0..<max(a.core.count, b.core.count) {
            let x = i < a.core.count ? a.core[i] : 0
            let y = i < b.core.count ? b.core[i] : 0
            if x != y { return x < y }
        }
        // Cores equal: a stable version (no prerelease) is greater than any prerelease.
        if a.pre.isEmpty || b.pre.isEmpty { return !a.pre.isEmpty && b.pre.isEmpty }
        for i in 0..<max(a.pre.count, b.pre.count) {
            if i >= a.pre.count { return true }   // shorter prerelease list ranks lower
            if i >= b.pre.count { return false }
            let ai = a.pre[i], bi = b.pre[i]
            if ai == bi { continue }
            if let an = Int(ai), let bn = Int(bi) { return an < bn }
            return ai < bi
        }
        return false
    }

    static func == (a: SemVer, b: SemVer) -> Bool {
        a.core == b.core && a.pre == b.pre
    }
}

enum UpdateError: LocalizedError {
    case network
    case notABundle
    case badArchive
    case signatureMismatch
    case installFailed
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .network: return "GitHub unreachable"
        case .notABundle: return "not running from an .app bundle"
        case .badArchive: return "no .app in the archive"
        case .signatureMismatch: return "signature verification failed"
        case .installFailed: return "could not replace the app"
        case .toolFailed(let tool): return "\(tool) failed"
        }
    }
}
