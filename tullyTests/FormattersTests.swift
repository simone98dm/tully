import Testing
@testable import tully

struct FormattersTests {
    @Test func rates() {
        #expect(formatRate(-5) == "0B/s")
        #expect(formatRate(840) == "840B/s")
        #expect(formatRate(12 * 1024) == "12KB/s")
        #expect(formatRate(3.4 * 1_048_576) == "3.4MB/s")
    }

    @Test func bytesNeverSayZero() {
        #expect(!formatBytes(0).lowercased().contains("zero"))
        #expect(formatBytes(UInt64(2) << 30).contains("GB"))
    }
}
