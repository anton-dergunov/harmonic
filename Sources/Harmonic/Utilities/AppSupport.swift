import Foundation

// The app's own files in ~/Library/Application Support/Harmonic.
//
// Writes are atomic and owner-only. These files hold the OAuth refresh token and
// queued user actions, both of which must survive an unclean shutdown —
// UserDefaults buffers writes through cfprefsd and can lose them.
enum AppSupport {

    private static let folderName = "Harmonic"

    static func fileURL(_ name: String) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(name)
    }

    static func read(_ name: String) -> Data? {
        guard let url = fileURL(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    static func write(_ data: Data, to name: String) -> Bool {
        guard let url = fileURL(name) else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // .atomic writes a temp file and renames it, so a crash mid-write leaves
        // the previous contents intact rather than a truncated file.
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    static func remove(_ name: String) {
        guard let url = fileURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // Shared coders: ISO-8601 dates keep the files readable by hand.

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
