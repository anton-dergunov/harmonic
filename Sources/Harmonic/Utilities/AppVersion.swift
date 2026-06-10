import Foundation

enum AppVersion {
    /// True unless running from an installed .app bundle with a real version string.
    static var isDevBuild: Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return true }
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v == nil || v == "Development"
    }

    static var displayString: String {
        guard !isDevBuild else { return "Development" }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    }
}
