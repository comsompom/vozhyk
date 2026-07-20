import CoreLocation
import CoreMotion
import Foundation

@MainActor
final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentHeading: CLHeading?
    @Published private(set) var relativeAltitudeMeters: Double?
    @Published private(set) var pressureKilopascals: Double?

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let altimeterQueue = OperationQueue()
    private var isUpdatingSensors = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.headingFilter = 1
        authorizationStatus = manager.authorizationStatus
        altimeterQueue.name = "com.vozhyk.drone-detector.altimeter"
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
        startSensorUpdatesIfAuthorized()
    }

    func stopSensorUpdates() {
        isUpdatingSensors = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.stopRelativeAltitudeUpdates()
        }
    }

    var sensorSnapshot: SensorSnapshot? {
        guard let location = currentLocation,
              let heading = currentHeading,
              location.horizontalAccuracy >= 0 else { return nil }

        let headingDegrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard headingDegrees >= 0 else { return nil }

        return SensorSnapshot(
            coordinate: location.coordinate,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            headingDegrees: headingDegrees,
            headingAccuracyDegrees: heading.headingAccuracy,
            relativeAltitudeMeters: relativeAltitudeMeters,
            pressureKilopascals: pressureKilopascals,
            capturedAt: Date()
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            startSensorUpdatesIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            currentHeading = newHeading
        }
    }

    private func startSensorUpdatesIfAuthorized() {
        guard !isUpdatingSensors else { return }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isUpdatingSensors = true
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
            startAltimeterIfAvailable()
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    private func startAltimeterIfAvailable() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: altimeterQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.relativeAltitudeMeters = data.relativeAltitude.doubleValue
                self.pressureKilopascals = data.pressure.doubleValue
            }
        }
    }
}
