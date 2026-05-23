import Foundation

@MainActor
final class LoggingSettings: ObservableObject {
    static let shared = LoggingSettings()

    @Published var loggingEnabled: Bool {
        didSet { UserDefaults.standard.set(loggingEnabled, forKey: "logging.enabled") }
    }

    @Published var logFilePath: String {
        didSet { UserDefaults.standard.set(logFilePath, forKey: "logging.filePath") }
    }

    private init() {
        loggingEnabled = UserDefaults.standard.bool(forKey: "logging.enabled")
        logFilePath = UserDefaults.standard.string(forKey: "logging.filePath") ?? LoggingSettings.defaultPath
    }

    private static var defaultPath: String {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/harmonic_log.jsonl")
            .path
    }
}
