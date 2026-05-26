import Sparkle

final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://raw.githubusercontent.com/simone98dm/tully/main/docs/appcast.xml"
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
