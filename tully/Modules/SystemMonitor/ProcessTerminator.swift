import Darwin
import Foundation

/// Sends SIGTERM and turns failures into readable messages.
nonisolated enum ProcessTerminator {
    enum Outcome: Equatable {
        case terminated
        case refused(String)
        case failed(String)
    }

    static let ownPID = getpid()

    static func canTerminate(_ pid: Int32) -> Bool { pid > 1 && pid != ownPID }

    /// `force` sends SIGKILL (Force Quit) instead of SIGTERM.
    /// `expectedPath`: the executable seen when the user chose to quit; if the pid now runs something
    /// else (pid reused while a dialog was open) nothing is sent.
    static func terminate(pid: Int32, name: String, force: Bool = false, expectedPath: String? = nil,
                          currentPath: (Int32) -> String? = { executablePath(of: $0) },
                          send: (Int32, Int32) -> Int32 = { Darwin.kill($0, $1) }) -> Outcome {
        guard canTerminate(pid) else { return .refused("tully can't quit \(name)") }
        if let expectedPath, !expectedPath.isEmpty, currentPath(pid) != expectedPath {
            return .failed("\(name) has already quit")
        }
        guard send(pid, force ? SIGKILL : SIGTERM) != 0 else { return .terminated }
        switch errno {
        case EPERM: return .failed("Couldn't quit \(name): permission denied")
        case ESRCH: return .failed("\(name) has already quit")
        default: return .failed("Couldn't quit \(name) (error \(errno))")
        }
    }

    static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
