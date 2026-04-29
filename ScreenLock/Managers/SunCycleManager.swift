import CoreLocation
import Foundation

final class SunCycleManager: NSObject, CLLocationManagerDelegate {
    static let shared = SunCycleManager()

    struct SunTimes {
        let sunrise: Date
        let sunset: Date
    }

    private let locationManager = CLLocationManager()
    private(set) var latestLocation: CLLocation?

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            locationManager.requestLocation()
        default:
            break
        }
    }

    func currentSunTimes(now: Date = Date()) -> SunTimes? {
        guard let location = latestLocation else { return nil }
        return computeSunTimes(for: location.coordinate, now: now)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func computeSunTimes(for coordinate: CLLocationCoordinate2D, now: Date) -> SunTimes? {
        let zenith = 90.833
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let longitudeHour = coordinate.longitude / 15.0

        guard
            let sunriseUTC = solarTimeUTC(dayOfYear: dayOfYear, latitude: coordinate.latitude, longitudeHour: longitudeHour, zenith: zenith, isSunrise: true),
            let sunsetUTC = solarTimeUTC(dayOfYear: dayOfYear, latitude: coordinate.latitude, longitudeHour: longitudeHour, zenith: zenith, isSunrise: false)
        else {
            return nil
        }

        let timeZoneOffset = Double(calendar.timeZone.secondsFromGMT(for: now)) / 3600.0
        let localSunriseHours = normalizedHours(sunriseUTC + timeZoneOffset)
        let localSunsetHours = normalizedHours(sunsetUTC + timeZoneOffset)

        let startOfDay = calendar.startOfDay(for: now)
        let sunrise = startOfDay.addingTimeInterval(localSunriseHours * 3600)
        let sunset = startOfDay.addingTimeInterval(localSunsetHours * 3600)
        return SunTimes(sunrise: sunrise, sunset: sunset)
    }

    private func solarTimeUTC(
        dayOfYear: Int,
        latitude: Double,
        longitudeHour: Double,
        zenith: Double,
        isSunrise: Bool
    ) -> Double? {
        let approximateTime = Double(dayOfYear) + ((isSunrise ? 6.0 : 18.0) - longitudeHour) / 24.0
        let meanAnomaly = (0.9856 * approximateTime) - 3.289
        let trueLongitude = normalizedDegrees(
            meanAnomaly
            + (1.916 * sin(degreesToRadians(meanAnomaly)))
            + (0.020 * sin(degreesToRadians(2 * meanAnomaly)))
            + 282.634
        )

        var rightAscension = radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
        rightAscension = normalizedDegrees(rightAscension)

        let longitudeQuadrant = floor(trueLongitude / 90.0) * 90.0
        let rightAscensionQuadrant = floor(rightAscension / 90.0) * 90.0
        rightAscension += longitudeQuadrant - rightAscensionQuadrant
        rightAscension /= 15.0

        let sinDeclination = 0.39782 * sin(degreesToRadians(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))
        let cosHourAngle =
            (cos(degreesToRadians(zenith)) - (sinDeclination * sin(degreesToRadians(latitude))))
            / (cosDeclination * cos(degreesToRadians(latitude)))

        guard cosHourAngle >= -1.0, cosHourAngle <= 1.0 else { return nil }

        let localHourAngle = isSunrise
            ? 360.0 - radiansToDegrees(acos(cosHourAngle))
            : radiansToDegrees(acos(cosHourAngle))
        let hourAngle = localHourAngle / 15.0

        let localMeanTime = hourAngle + rightAscension - (0.06571 * approximateTime) - 6.622
        let utc = normalizedHours(localMeanTime - longitudeHour)
        return utc
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360.0)
        if result < 0 { result += 360.0 }
        return result
    }

    private func normalizedHours(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 24.0)
        if result < 0 { result += 24.0 }
        return result
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
