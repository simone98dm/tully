import Darwin
import Testing
@testable import tully

struct ProcessTerminatorTests {
    @Test func refusesOwnProcessAndLaunchd() {
        #expect(ProcessTerminator.terminate(pid: ProcessTerminator.ownPID, name: "tully", send: { _, _ in 0 }) == .refused("tully can't quit tully"))
        #expect(!ProcessTerminator.canTerminate(1))
    }

    @Test func reportsSuccessAndErrno() {
        #expect(ProcessTerminator.terminate(pid: 999, name: "X", send: { _, _ in 0 }) == .terminated)
        let denied = ProcessTerminator.terminate(pid: 999, name: "X", send: { _, _ in errno = EPERM; return -1 })
        #expect(denied == .failed("Couldn't quit X: permission denied"))
        let gone = ProcessTerminator.terminate(pid: 999, name: "X", send: { _, _ in errno = ESRCH; return -1 })
        #expect(gone == .failed("X has already quit"))
    }

    @Test func reusedPidIsNotSignalled() {
        var sent = false
        let outcome = ProcessTerminator.terminate(pid: 999, name: "Old", expectedPath: "/Applications/Old.app/Contents/MacOS/Old",
                                                  currentPath: { _ in "/usr/bin/something-else" },
                                                  send: { _, _ in sent = true; return 0 })
        #expect(outcome == .failed("Old has already quit") && !sent)
    }
}
