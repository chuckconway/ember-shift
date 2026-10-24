import CoreLocation
import EmberCore

/// One-shot, city-level location lookup for sunrise/sunset times.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<Coordinate, Error>) -> Void)?

    struct Denied: LocalizedError {
        var errorDescription: String? { "Location access is off. Allow Ember Shift in System Settings → Privacy & Security → Location Services, or enter coordinates." }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(_ completion: @escaping (Result<Coordinate, Error>) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(Denied()))
        default: manager.requestLocation()
        }
    }

    private func finish(_ result: Result<Coordinate, Error>) {
        completion?(result)
        completion = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard completion != nil else { return }
            switch manager.authorizationStatus {
            case .notDetermined: break
            case .denied, .restricted: finish(.failure(Denied()))
            default: manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            finish(.success(Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }
}
