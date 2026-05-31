import Foundation
import HealthKit
import WatchConnectivity

final class HeartRateManager: NSObject, ObservableObject {
    @Published var currentBPM: Int?
    @Published var isRunning = false
    @Published var status = "測定を開始してください"

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    override init() {
        super.init()
        activateWatchConnectivity()
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "HealthKitを利用できません"
            return
        }

        let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate)!
        healthStore.requestAuthorization(toShare: [], read: [heartRate]) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.currentBPM = nil
                    self.startWorkoutSession()
                    self.startHeartRateQuery()
                    self.isRunning = true
                    self.status = "測定中"
                } else {
                    self.status = error?.localizedDescription ?? "HealthKitの許可が必要です"
                }
            }
        }
    }

    func stop() {
        stop(status: "停止しました")
    }

    private func stop(status: String) {
        if let query {
            healthStore.stop(query)
        }
        workoutSession?.end()
        query = nil
        workoutSession = nil
        isRunning = false
        self.status = status
    }

    private func startWorkoutSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown
        workoutSession = try? HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        workoutSession?.startActivity(with: Date())
    }

    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            self?.handle(samples: samples, anchor: newAnchor, error: error)
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            self?.handle(samples: samples, anchor: newAnchor, error: error)
        }

        self.query = query
        healthStore.execute(query)
    }

    private func handle(samples: [HKSample]?, anchor: HKQueryAnchor?, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.status = error.localizedDescription
                return
            }

            self.anchor = anchor
            guard
                let sample = samples?.compactMap({ $0 as? HKQuantitySample }).last
            else { return }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let bpm = Int(sample.quantity.doubleValue(for: unit).rounded())
            self.currentBPM = bpm
            self.sendToPhone(bpm: bpm)
            self.stop(status: "測定完了")
        }
    }

    private func activateWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func sendToPhone(bpm: Int) {
        let message: [String: Any] = [
            WatchHeartRateMessage.bpm: bpm,
            WatchHeartRateMessage.timestamp: Date().timeIntervalSince1970,
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        }

        try? WCSession.default.updateApplicationContext(message)
    }
}

extension HeartRateManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
