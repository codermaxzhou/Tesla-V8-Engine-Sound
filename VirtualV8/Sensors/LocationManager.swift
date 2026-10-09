import CoreLocation
import Observation

@MainActor @Observable final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isSampling = false
    private(set) var errorMessage: String?
    @ObservationIgnored var onSample: ((LocationSample) -> Void)?
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var requested = false

    var permissionLabel: String {
        switch authorization {
        case .authorizedAlways: return "Authorized"
        #if os(iOS)
        case .authorizedWhenInUse: return "Authorized"
        #endif
        case .denied: return "Denied — enable Location in Settings"
        case .restricted: return "Restricted"
        default: return "Permission needed"
        }
    }

    func start() {
        requested = true
        if manager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = false
            self.manager = manager
        }
        guard let manager else { return }
        authorization = manager.authorizationStatus
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { beginIfAuthorized() }
    }

    func stop() {
        requested = false
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        isSampling = false
    }

    private func beginIfAuthorized() {
        #if os(iOS)
        let authorized = authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        #else
        let authorized = authorization == .authorizedAlways
        #endif
        guard requested, authorized else {
            manager?.stopUpdatingLocation(); isSampling = false; return
        }
        errorMessage = nil
        manager?.startUpdatingLocation()
        isSampling = true
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let identity = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, let active = self.manager, ObjectIdentifier(active) == identity else { return }
            self.authorization = status
            self.beginIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let identity = ObjectIdentifier(manager)
        let samples = locations.map {
            LocationSample(speedKmh: $0.speed * 3.6, timestamp: $0.timestamp.timeIntervalSince1970,
                           horizontalAccuracy: $0.horizontalAccuracy, speedAccuracy: $0.speedAccuracy)
        }
        Task { @MainActor [weak self] in
            guard let self, self.requested, let active = self.manager, ObjectIdentifier(active) == identity else { return }
            self.errorMessage = nil
            for sample in samples { self.onSample?(sample) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let identity = ObjectIdentifier(manager)
        let message = (error as? CLError)?.code == .locationUnknown ? "GPS temporarily unavailable" : error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, self.requested, let active = self.manager, ObjectIdentifier(active) == identity else { return }
            self.errorMessage = message
        }
    }
}
