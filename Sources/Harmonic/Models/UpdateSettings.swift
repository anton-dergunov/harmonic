import Foundation

@MainActor
final class UpdateSettings: ObservableObject {
    static let shared = UpdateSettings()

    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "harmonic.updates.autoCheck") }
    }

    @Published var autoInstall: Bool {
        didSet { UserDefaults.standard.set(autoInstall, forKey: "harmonic.updates.autoInstall") }
    }

    var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: "harmonic.updates.lastCheckDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "harmonic.updates.lastCheckDate") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "harmonic.updates.autoCheck") == nil {
            autoCheck = true
        } else {
            autoCheck = UserDefaults.standard.bool(forKey: "harmonic.updates.autoCheck")
        }
        autoInstall = UserDefaults.standard.bool(forKey: "harmonic.updates.autoInstall")
    }
}
