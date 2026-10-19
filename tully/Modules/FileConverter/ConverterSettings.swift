import AppKit
import KumquatCore

/// File Converter preferences, persisted under `tully.converter.*` keys.
@Observable
final class ConverterSettings {
    static let shared = ConverterSettings(defaults: AppEnvironment.defaults)
    static let keyPrefix = "tully.converter."
    static let recentsLimit = 10
    static let moveFoldersLimit = 5

    @ObservationIgnored private let defaults: UserDefaults

    /// Master switch: the wheels watch drags only while this is on. On by default.
    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Self.key("enabled")) } }
    var binding: ModifierBinding { didSet { defaults.set(try? JSONEncoder().encode(binding), forKey: Self.key("binding")) } }
    var useCustomFolder: Bool { didSet { defaults.set(useCustomFolder, forKey: Self.key("useCustomFolder")) } }
    var customFolder: String { didSet { defaults.set(customFolder, forKey: Self.key("customFolder")) } }
    var revealOutput: Bool { didSet { defaults.set(revealOutput, forKey: Self.key("revealOutput")) } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Self.key("hasOnboarded")) } }
    private(set) var recents: [String]
    /// Most recent Move destinations, newest first.
    @ObservationIgnored private(set) var moveFolders: [String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.key("enabled")) as? Bool ?? true
        binding = defaults.data(forKey: Self.key("binding")).flatMap { try? JSONDecoder().decode(ModifierBinding.self, from: $0) } ?? .default
        useCustomFolder = defaults.bool(forKey: Self.key("useCustomFolder"))
        customFolder = defaults.string(forKey: Self.key("customFolder"))
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        revealOutput = defaults.bool(forKey: Self.key("revealOutput"))
        hasOnboarded = defaults.bool(forKey: Self.key("hasOnboarded"))
        recents = defaults.stringArray(forKey: Self.key("recents")) ?? []
        moveFolders = defaults.stringArray(forKey: Self.key("moveFolders")) ?? []
    }

    static func key(_ name: String) -> String { keyPrefix + name }

    var outputFolder: URL? { useCustomFolder ? URL(fileURLWithPath: customFolder) : nil }

    func addRecents(_ urls: [URL]) {
        let paths = urls.map(\.path)
        recents = Array((paths + recents.filter { !paths.contains($0) }).prefix(Self.recentsLimit))
        defaults.set(recents, forKey: Self.key("recents"))
    }

    func addMoveFolder(_ url: URL) {
        moveFolders = Array(([url.path] + moveFolders.filter { $0 != url.path }).prefix(Self.moveFoldersLimit))
        defaults.set(moveFolders, forKey: Self.key("moveFolders"))
    }

    func clearRecents() {
        recents = []
        defaults.set(recents, forKey: Self.key("recents"))
    }

    func reset() {
        ["enabled", "binding", "useCustomFolder", "customFolder", "revealOutput", "hasOnboarded", "recents", "moveFolders"]
            .forEach { defaults.removeObject(forKey: Self.key($0)) }
        isEnabled = true
        binding = .default
        useCustomFolder = false
        revealOutput = false
        recents = []
        moveFolders = []
    }

    /// Binding where two wheels share the same keys (the first one wins).
    var hasConflict: Bool { Set([binding.convert, binding.tools, binding.actions]).count < 3 }
}
