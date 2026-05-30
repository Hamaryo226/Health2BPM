import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate {
    var onHeartRate: ((Int) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bpm = message[WatchHeartRateMessage.bpm] as? Int else { return }
        onHeartRate?(bpm)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let bpm = applicationContext[WatchHeartRateMessage.bpm] as? Int else { return }
        onHeartRate?(bpm)
    }
}
