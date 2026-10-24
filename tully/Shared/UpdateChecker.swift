import AppKit
import Foundation

/// Daily check of the latest GitHub release (published by scripts/release.sh as tag vX.Y.Z).
@Observable
final class UpdateChecker {
    private enum Key {
        static let enabled = "tully.checkUpdates"
        static let lastCheck = "tully.lastUpdateCheck"
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/simone98dm/tully/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// How often we look whether a check is due; survives sleep better than one 24 h timer.
    private static let pollInterval: TimeInterval = 60 * 60

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            isEnabled ? start() : stop()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
    }

    func start() {
        guard isEnabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        checkIfDue()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        defaults.removeObject(forKey: Key.lastCheck)
        isEnabled = true
    }

    private func checkIfDue() {
        let last = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        guard isEnabled, Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        Task { await check() }
    }

    private func check() async {
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                NSLog("tully: update check got HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            defaults.set(Date(), forKey: Key.lastCheck)
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if isEnabled, Self.isNewer(release.tagName, than: current) { offer(release) }
        } catch {
            // offline or GitHub down: lastCheck stays old, so the next poll retries
            NSLog("tully: update check failed: \(error)")
        }
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "A new version of tully is available"
        alert.informativeText = "\(release.tagName) is out. Open the release page to download it."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
    }

    /// Compares dotted versions numerically; a leading "v" is ignored ("v2.10.0" > "2.9.1").
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let (r, l) = (parts(remote), parts(local))
        for i in 0..<max(r.count, l.count) {
            let (a, b) = (i < r.count ? r[i] : 0, i < l.count ? l[i] : 0)
            if a != b { return a > b }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
