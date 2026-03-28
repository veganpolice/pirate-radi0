import Foundation

/// Test mock for SpeedProvider. Push speeds with send(speed:), end with finish().
actor MockSpeedProvider: SpeedProvider {
    let speedStream: AsyncStream<Double>
    private let continuation: AsyncStream<Double>.Continuation

    // MARK: - Call Tracking

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var sentSpeeds: [Double] = []

    init() {
        let (stream, cont) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        self.speedStream = stream
        self.continuation = cont
    }

    // MARK: - SpeedProvider

    func startUpdating() async {
        startCallCount += 1
    }

    func stopUpdating() async {
        stopCallCount += 1
    }

    // MARK: - Test Helpers

    func send(speed: Double) {
        sentSpeeds.append(speed)
        continuation.yield(speed)
    }

    func finish() {
        continuation.finish()
    }

    func reset() {
        startCallCount = 0
        stopCallCount = 0
        sentSpeeds = []
    }
}
