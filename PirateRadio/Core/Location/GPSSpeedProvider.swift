import Foundation
import CoreLocation

/// Provides speed data from GPS via CLLocationManager.
final class GPSSpeedProvider: NSObject, SpeedProvider, CLLocationManagerDelegate {
    let speedStream: AsyncStream<Double>
    private let continuation: AsyncStream<Double>.Continuation
    private let locationManager: CLLocationManager

    private static let metersPerSecondToMPH: Double = 2.23694

    override init() {
        let (stream, cont) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        self.speedStream = stream
        self.continuation = cont
        self.locationManager = CLLocationManager()

        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 5
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }

    func startUpdating() async {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() async {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // CLLocation.speed is m/s, negative means invalid
        let speedMPH = max(0, location.speed * Self.metersPerSecondToMPH)
        continuation.yield(speedMPH)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[GPSSpeed] Location error: \(error.localizedDescription)")
        #endif
    }

    deinit {
        continuation.finish()
    }
}
