import Foundation

/// Launch flags and run-mode checks.
nonisolated enum AppEnvironment {
    static let arguments = Foundation.ProcessInfo.processInfo.arguments

    /// Hosted unit tests load the app; skip side effects (event taps, status item, sampling).
    static let isRunningUnitTests = Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        && !arguments.contains("--ui-testing")

    /// UI tests: isolated defaults, no event taps or global monitors.
    static let isUITesting = arguments.contains("--ui-testing")

    /// Screenshots: fixed sample data instead of live sampling.
    static let usesDemoData = arguments.contains("--demo-data")

    static func value(for flag: String) -> String? {
        if let match = arguments.first(where: { $0.hasPrefix(flag + "=") }) {
            return String(match.dropFirst(flag.count + 1))
        }
        return arguments.contains(flag) ? "" : nil
    }

    /// Full app with a throwaway settings store (profiling, demos) — real settings stay untouched.
    static let usesIsolatedDefaults = isUITesting || usesDemoData || arguments.contains("--isolated-defaults")

    /// Defaults store: a throwaway suite while UI testing or profiling so runs never touch real settings.
    static let defaults: UserDefaults = {
        guard usesIsolatedDefaults else { return .standard }
        let name = "tully.uitests"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }()
}
