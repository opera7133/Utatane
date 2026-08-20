import CoreLocation
import Foundation

struct CurrentWeather: Sendable, Equatable {
    let code: Int
    let temperatureCelsius: Double
    let isDay: Bool
}

enum CurrentWeatherError: Error {
    case locationServicesUnavailable
    case locationPermissionDenied
    case locationTimedOut
    case invalidResponse
}

@MainActor
final class CurrentWeatherProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func fetch() async throws -> CurrentWeather {
        let location = try await requestLocation()
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { throw CurrentWeatherError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode)
        else { throw CurrentWeatherError.invalidResponse }
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return CurrentWeather(
            code: payload.current.weatherCode,
            temperatureCelsius: payload.current.temperature,
            isDay: payload.current.isDay == 1
        )
    }

    private func requestLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw CurrentWeatherError.locationServicesUnavailable
        }
        guard locationContinuation == nil else {
            throw CurrentWeatherError.locationServicesUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(CurrentWeatherError.locationTimedOut))
            }
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                manager.startUpdatingLocation()
            case .notDetermined:
                // macOS asks for authorization when a location service starts.
                manager.startUpdatingLocation()
            case .denied, .restricted:
                finish(with: .failure(CurrentWeatherError.locationPermissionDenied))
            @unknown default:
                finish(with: .failure(CurrentWeatherError.locationServicesUnavailable))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard locationContinuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            finish(with: .failure(CurrentWeatherError.locationPermissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(CurrentWeatherError.locationServicesUnavailable))
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(CurrentWeatherError.locationServicesUnavailable))
            return
        }
        finish(with: .success(location))
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = locationContinuation
        locationContinuation = nil
        continuation?.resume(with: result)
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    let current: Current
}
