import AppKit
import Combine
import Foundation

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    let tagName: String
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }

    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    var dmgAsset: Asset? { assets.first { $0.name.hasSuffix(".dmg") } }
}

@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    @Published var updateAvailable: GitHubRelease?
    @Published var downloadProgress: Double = 0
    @Published var isChecking = false
    @Published var isInstalling = false
    @Published var statusMessage: String?

    private let releasesURL = URL(string: "https://api.github.com/repos/anton-dergunov/harmonic/releases/latest")!
    private var dailyTimer: AnyCancellable?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    // True when the app is running from a source build with no proper version string.
    // Dev builds should never receive automatic update prompts.
    var isDevVersion: Bool {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v == nil || v == "Development"
    }

    func checkOnLaunchIfNeeded() {
        guard !isDevVersion else { return }
        let settings = UpdateSettings.shared
        guard settings.autoCheck else { return }
        let shouldCheck = settings.lastCheckDate.map { Date().timeIntervalSince($0) > 23 * 3600 } ?? true
        if shouldCheck {
            Task { await checkForUpdates(force: false, forceAnyVersion: false) }
        }
        scheduleDailyTimer()
    }

    // force: show result to user even when already up to date.
    // forceAnyVersion: treat whatever is on GitHub as newer (Shift+click testing path).
    func checkForUpdates(force: Bool, forceAnyVersion: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            UpdateSettings.shared.lastCheckDate = Date()
            if forceAnyVersion || isNewerThanCurrent(release.version) {
                updateAvailable = release
                let settings = UpdateSettings.shared
                if force || !settings.autoInstall {
                    showUpdateAlert(release)
                } else {
                    await performInstall(release)
                }
            } else {
                updateAvailable = nil
                if force { statusMessage = "You're up to date." }
            }
        } catch {
            if force { statusMessage = "Update check failed: \(error.localizedDescription)" }
        }
    }

    func installUpdate() {
        guard let release = updateAvailable else { return }
        Task { await performInstall(release) }
    }

    // MARK: - Private

    private func scheduleDailyTimer() {
        dailyTimer = Timer.publish(every: 24 * 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard UpdateSettings.shared.autoCheck else { return }
                Task { await self?.checkForUpdates(force: false, forceAnyVersion: false) }
            }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func isNewerThanCurrent(_ version: String) -> Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return compareVersions(version, current) > 0
    }

    private func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(aParts.count, bParts.count)
        for i in 0..<maxLen {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av > bv ? 1 : -1 }
        }
        return 0
    }

    // NSApp.applicationIconImage and NSWorkspace.icon(forFile:) both return generic icons
    // for LSBackgroundOnly apps. Load lotus.icns directly from the bundle resources.
    private var appIcon: NSImage? {
        if let path = Bundle.main.path(forResource: "lotus", ofType: "icns") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    private func showUpdateAlert(_ release: GitHubRelease) {
        let alert = NSAlert()
        if let icon = appIcon { alert.icon = icon }
        alert.messageText = "Harmonic \(release.version) is available"
        alert.informativeText = "Release notes:"
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = release.body ?? "(no release notes)"
        textView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        alert.accessoryView = scrollView

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await performInstall(release) }
        }
    }

    // Returns the path to the running .app bundle, or looks up the installed copy
    // by bundle identifier. Needed when testing from a raw dev-build executable,
    // where Bundle.main.bundlePath is not a .app bundle.
    private func findAppBundlePath() -> String? {
        let path = Bundle.main.bundlePath
        if path.hasSuffix(".app") { return path }
        return NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.adergunov.harmonic")?
            .path
    }

    private func performInstall(_ release: GitHubRelease) async {
        guard let asset = release.dmgAsset else {
            showError("No .dmg file found in this release.")
            return
        }
        isInstalling = true
        downloadProgress = 0
        defer { isInstalling = false }

        let dmgURL: URL
        do {
            dmgURL = try await downloadAsset(asset)
        } catch {
            showError("Download failed: \(error.localizedDescription)")
            return
        }

        guard let dest = findAppBundlePath() else {
            showError("Could not locate Harmonic.app to update. Please install manually from GitHub.")
            return
        }
        let mountPoint = "/tmp/HarmonicUpdateMount"
        let appInMount = "\(mountPoint)/Harmonic.app"

        do {
            try shell("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-quiet", "-mountpoint", mountPoint])
        } catch {
            showError("Could not mount the update disk image: \(error.localizedDescription)")
            return
        }

        let dittoOK = (try? shell("/usr/bin/ditto", [appInMount, dest])) != nil
        _ = try? shell("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"])
        try? FileManager.default.removeItem(at: dmgURL)

        if !dittoOK {
            showInstallFailureAlert()
            return
        }

        showRestartPrompt(dest: dest)
    }

    @discardableResult
    private func shell(_ path: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "UpdateService", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func downloadAsset(_ asset: GitHubRelease.Asset) async throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarmonicUpdate-\(UUID().uuidString).dmg")

        let (tmpURL, _) = try await URLSession.shared.download(from: asset.browserDownloadUrl) { [weak self] received, expected, _ in
            guard let self, expected > 0 else { return }
            Task { @MainActor in self.downloadProgress = Double(received) / Double(expected) }
        }

        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    private func showRestartPrompt(dest: String) {
        let alert = NSAlert()
        if let icon = appIcon { alert.icon = icon }
        alert.messageText = "Update installed"
        alert.informativeText = "Harmonic has been updated. Restart now to use the new version."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch(dest: dest)
        }
    }

    private func relaunch(dest: String) {
        let script = "/tmp/harmonic_relaunch.sh"
        let content = "#!/bin/sh\nsleep 1\nopen \"\(dest)\"\n"
        try? content.write(toFile: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [script]
        try? proc.run()
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showInstallFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "Could not install the update"
        alert.informativeText = "Harmonic could not copy the new version to its current location. You may need to open Privacy & Security settings and allow the app to run, or install manually from GitHub."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Privacy & Security")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        }
    }
}

// URLSession download with progress callback (no async/throws variant in stdlib pre-macOS 15).
private extension URLSession {
    func download(from url: URL, progress: @escaping (Int64, Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: url) { url, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url, let response else {
                    continuation.resume(throwing: URLError(.unknown)); return
                }
                continuation.resume(returning: (url, response))
            }
            task.resume()
        }
    }
}
