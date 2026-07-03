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

    /// Returns the latest release if it is strictly newer than the running version.
    static func checkForUpdate() async throws -> Release? {
        guard let current = currentVersion else { return nil }
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.network }
        if http.statusCode == 404 { return nil } // no release published yet
        guard http.statusCode == 200 else { throw UpdateError.network }

        let dto = try JSONDecoder().decode(ReleaseDTO.self, from: data)
        let version = dto.tagName.hasPrefix("v") ? String(dto.tagName.dropFirst()) : dto.tagName
        guard isVersion(version, newerThan: current),
              let asset = dto.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let zipURL = URL(string: asset.browserDownloadUrl) else {
            return nil
        }
        return Release(version: version, zipURL: zipURL)
    }

    /// Numeric dot-component comparison ("0.10.0" > "0.9.1").
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
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
            case assets
        }
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
