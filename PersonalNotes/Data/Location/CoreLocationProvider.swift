import CoreLocation
import Foundation

/// Resolves "where am I" for a note through CoreLocation, then reverse geocodes the result into a
/// short human label.
///
/// A failure to geocode is not an error: the note keeps its coordinates and shows them instead.
final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    struct LocationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> NoteLocation {
        try await ensureAuthorized()
        let location = try await awaitFix()
        let label = await reverseGeocode(location)
        return NoteLocation(
            label: label ?? Self.format(location.coordinate),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    // MARK: - Authorization

    private func ensureAuthorized() async throws {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return
        case .denied, .restricted:
            throw LocationError(message: "Location access is turned off for Personal Notes")
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                throw LocationError(message: "Location permission is needed to tag this note")
            }
        @unknown default:
            throw LocationError(message: "Location is unavailable")
        }
    }

    // MARK: - A fix

    private func awaitFix() async throws -> CLLocation {
        if let cached = manager.location, abs(cached.timestamp.timeIntervalSinceNow) < 60 {
            return cached
        }
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw LocationError(message: "Location is unavailable") }
                return try await withCheckedThrowingContinuation { continuation in
                    self.locationContinuation = continuation
                    self.manager.requestLocation()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 12_000_000_000)
                throw LocationError(message: "The location could not be read in time")
            }
            guard let first = try await group.next() else {
                throw LocationError(message: "No location fix available")
            }
            group.cancelAll()
            return first
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        let marks = try? await geocoder.reverseGeocodeLocation(location)
        guard let place = marks?.first else { return nil }
        let parts = [place.locality, place.administrativeArea, place.country]
            .compactMap { $0 }
            .uniqued()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func format(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation, let location = locations.last else { return }
        locationContinuation = nil
        continuation.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: LocationError(message: error.localizedDescription))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
