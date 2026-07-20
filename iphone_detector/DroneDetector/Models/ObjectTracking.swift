import CoreGraphics
import CoreLocation
import Foundation

struct ObjectDistanceEstimate {
    let detection: VisionDetection
    let distanceMeters: CGFloat

    var objectTitle: String {
        detection.objectType.title
    }

    var formattedDistance: String {
        if distanceMeters >= 100 {
            return String(format: "~%.0f m", distanceMeters)
        }
        if distanceMeters >= 10 {
            return String(format: "~%.1f m", distanceMeters)
        }
        return String(format: "~%.2f m", distanceMeters)
    }
}

enum ObjectDistanceEstimator {
    static func estimates(
        in detections: [VisionDetection],
        enabledTypes: Set<DetectableObjectType>,
        frameAspectRatio: CGFloat,
        horizontalFieldOfViewDegrees: CGFloat,
        zoomFactor: CGFloat
    ) -> [ObjectDistanceEstimate] {
        guard !enabledTypes.isEmpty else { return [] }

        let axisFOV = effectiveAxisFieldOfViews(
            frameAspectRatio: frameAspectRatio,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            zoomFactor: zoomFactor
        )

        return detections
            .filter { enabledTypes.contains($0.objectType) }
            .compactMap { estimate(for: $0, horizontalFOV: axisFOV.horizontal, verticalFOV: axisFOV.vertical) }
    }

    static func nearestEstimate(
        in detections: [VisionDetection],
        enabledTypes: Set<DetectableObjectType>,
        frameAspectRatio: CGFloat,
        horizontalFieldOfViewDegrees: CGFloat,
        zoomFactor: CGFloat
    ) -> ObjectDistanceEstimate? {
        estimates(
            in: detections,
            enabledTypes: enabledTypes,
            frameAspectRatio: frameAspectRatio,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            zoomFactor: zoomFactor
        )
        .min { $0.distanceMeters < $1.distanceMeters }
    }

    static func effectiveAxisFieldOfViews(
        frameAspectRatio: CGFloat,
        horizontalFieldOfViewDegrees: CGFloat,
        zoomFactor: CGFloat
    ) -> (horizontal: CGFloat, vertical: CGFloat) {
        let safeAspectRatio = max(frameAspectRatio, 0.01)
        let baseHorizontal = horizontalFieldOfViewDegrees * .pi / 180
        let safeZoom = max(zoomFactor, 1.0)
        let effectiveBaseHorizontal = 2 * atan(tan(baseHorizontal / 2) / safeZoom)

        if safeAspectRatio < 1 {
            let vertical = effectiveBaseHorizontal
            let horizontal = 2 * atan(tan(vertical / 2) * safeAspectRatio)
            return (horizontal, vertical)
        }

        let horizontal = effectiveBaseHorizontal
        let vertical = 2 * atan(tan(horizontal / 2) / safeAspectRatio)
        return (horizontal, vertical)
    }

    private static func estimate(
        for detection: VisionDetection,
        horizontalFOV: CGFloat,
        verticalFOV: CGFloat
    ) -> ObjectDistanceEstimate? {
        switch detection.objectType {
        case .human:
            return distance(
                detection: detection,
                realMeters: 1.75,
                normalizedSpan: detection.boundingBox.height,
                fieldOfViewRadians: verticalFOV
            )
        case .auto:
            let majorSpan = max(detection.boundingBox.width, detection.boundingBox.height)
            let majorFOV = detection.boundingBox.width >= detection.boundingBox.height ? horizontalFOV : verticalFOV
            return distance(
                detection: detection,
                realMeters: (2.5 + 3.3) / 2,
                normalizedSpan: majorSpan,
                fieldOfViewRadians: majorFOV
            )
        case .planeDrone:
            let wingspan = distanceMeters(
                realMeters: 2.7,
                normalizedSpan: detection.boundingBox.width,
                fieldOfViewRadians: horizontalFOV
            )
            let fuselage = distanceMeters(
                realMeters: 2.5,
                normalizedSpan: detection.boundingBox.height,
                fieldOfViewRadians: verticalFOV
            )
            let values = [wingspan, fuselage].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return ObjectDistanceEstimate(
                detection: detection,
                distanceMeters: values.reduce(0, +) / CGFloat(values.count)
            )
        case .drone:
            let majorSpan = max(detection.boundingBox.width, detection.boundingBox.height)
            let majorFOV = detection.boundingBox.width >= detection.boundingBox.height ? horizontalFOV : verticalFOV
            return distance(
                detection: detection,
                realMeters: 0.45,
                normalizedSpan: majorSpan,
                fieldOfViewRadians: majorFOV
            )
        case .plane, .bird, .bus, .truck, .motorcycle:
            return nil
        }
    }

    private static func distance(
        detection: VisionDetection,
        realMeters: CGFloat,
        normalizedSpan: CGFloat,
        fieldOfViewRadians: CGFloat
    ) -> ObjectDistanceEstimate? {
        guard let meters = distanceMeters(
            realMeters: realMeters,
            normalizedSpan: normalizedSpan,
            fieldOfViewRadians: fieldOfViewRadians
        ) else { return nil }

        return ObjectDistanceEstimate(detection: detection, distanceMeters: meters)
    }

    private static func distanceMeters(
        realMeters: CGFloat,
        normalizedSpan: CGFloat,
        fieldOfViewRadians: CGFloat
    ) -> CGFloat? {
        guard normalizedSpan > 0.001, fieldOfViewRadians > 0 else { return nil }
        let focalLengthInNormalizedPixels = 0.5 / tan(fieldOfViewRadians / 2)
        let meters = focalLengthInNormalizedPixels * realMeters / normalizedSpan
        guard meters.isFinite, meters > 0 else { return nil }
        return meters
    }
}

struct SensorSnapshot {
    let coordinate: CLLocationCoordinate2D
    let horizontalAccuracyMeters: CLLocationAccuracy
    let altitudeMeters: CLLocationDistance?
    let headingDegrees: CLLocationDirection
    let headingAccuracyDegrees: CLLocationDirection
    let relativeAltitudeMeters: Double?
    let pressureKilopascals: Double?
    let capturedAt: Date
}

struct ObjectTrackLogEntry: Codable, Identifiable {
    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
    }

    struct Movement: Codable {
        let distanceFromPreviousMeters: Double
        let bearingFromPreviousDegrees: Double
        let speedMetersPerSecond: Double
        let predictedLatitude: Double
        let predictedLongitude: Double
    }

    let id: UUID
    let trackID: UUID
    let detectedAt: Date
    let trackedAt: Date
    let objectType: String
    let objectTitle: String
    let confidence: Float
    let distanceMeters: Double
    let objectCoordinate: Coordinate
    let phoneCoordinate: Coordinate
    let phoneHorizontalAccuracyMeters: Double
    let phoneAltitudeMeters: Double?
    let headingDegrees: Double
    let headingAccuracyDegrees: Double
    let relativeAltitudeMeters: Double?
    let pressureKilopascals: Double?
    let movement: Movement?
}

@MainActor
final class ObjectTrackLogger: ObservableObject {
    @Published private(set) var entries: [ObjectTrackLogEntry] = []
    @Published private(set) var statusMessage = "Track logging off"

    private struct ActiveTrack {
        let id: UUID
        var objectType: DetectableObjectType
        var boundingBox: CGRect
        var lastLoggedAt: Date
        var lastCoordinate: CLLocationCoordinate2D
    }

    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let fileURL: URL
    private var activeTracks: [ActiveTrack] = []

    private let minimumLogInterval: TimeInterval = 1.0
    private let trackStaleInterval: TimeInterval = 6.0
    private let trackMatchIoU: CGFloat = 0.2
    private let maxVisibleEntries = 200

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDirectory = directory.appendingPathComponent("Vozhyk", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        fileURL = appDirectory.appendingPathComponent("object_track_log.jsonl")

        loadRecentEntries()
        statusMessage = entries.isEmpty ? "No track logs yet" : "\(entries.count) recent track logs loaded"
    }

    var logFilePath: String {
        fileURL.path
    }

    func record(
        detections: [VisionDetection],
        enabledTypes: Set<DetectableObjectType>,
        sensor: SensorSnapshot?,
        frameAspectRatio: CGFloat,
        horizontalFieldOfViewDegrees: CGFloat,
        zoomFactor: CGFloat
    ) {
        guard !enabledTypes.isEmpty else {
            statusMessage = "Track logging off"
            return
        }

        guard let sensor else {
            statusMessage = "Waiting for GPS and compass"
            return
        }

        let now = Date()
        activeTracks.removeAll { now.timeIntervalSince($0.lastLoggedAt) > trackStaleInterval }

        let estimates = ObjectDistanceEstimator.estimates(
            in: detections,
            enabledTypes: enabledTypes,
            frameAspectRatio: frameAspectRatio,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            zoomFactor: zoomFactor
        )

        guard !estimates.isEmpty else {
            statusMessage = "No trackable distance estimates"
            return
        }

        var appended = 0
        let axisFOV = ObjectDistanceEstimator.effectiveAxisFieldOfViews(
            frameAspectRatio: frameAspectRatio,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            zoomFactor: zoomFactor
        )

        for estimate in estimates {
            guard let entry = makeEntry(
                for: estimate,
                sensor: sensor,
                horizontalFOV: axisFOV.horizontal,
                now: now
            ) else { continue }
            append(entry)
            appended += 1
        }

        if appended > 0 {
            statusMessage = "Saved \(appended) track log\(appended == 1 ? "" : "s")"
        }
    }

    func clearLogs() {
        entries = []
        activeTracks = []
        try? FileManager.default.removeItem(at: fileURL)
        statusMessage = "Track logs cleared"
    }

    private func makeEntry(
        for estimate: ObjectDistanceEstimate,
        sensor: SensorSnapshot,
        horizontalFOV: CGFloat,
        now: Date
    ) -> ObjectTrackLogEntry? {
        let detection = estimate.detection
        let bearing = objectBearingDegrees(
            phoneHeadingDegrees: sensor.headingDegrees,
            boundingBox: detection.boundingBox,
            horizontalFOV: horizontalFOV
        )
        let objectCoordinate = Self.destinationCoordinate(
            from: sensor.coordinate,
            distanceMeters: Double(estimate.distanceMeters),
            bearingDegrees: bearing
        )
        let track = matchedTrack(
            objectType: detection.objectType,
            boundingBox: detection.boundingBox,
            objectCoordinate: objectCoordinate,
            now: now
        )

        guard now.timeIntervalSince(track.lastLoggedAt) >= minimumLogInterval else { return nil }

        let movement = movementEntry(
            from: track.lastCoordinate,
            to: objectCoordinate,
            elapsed: now.timeIntervalSince(track.lastLoggedAt)
        )

        updateTrack(
            id: track.id,
            objectType: detection.objectType,
            boundingBox: detection.boundingBox,
            coordinate: objectCoordinate,
            now: now
        )

        return ObjectTrackLogEntry(
            id: UUID(),
            trackID: track.id,
            detectedAt: now,
            trackedAt: sensor.capturedAt,
            objectType: detection.objectType.rawValue,
            objectTitle: detection.objectType.title,
            confidence: detection.confidence,
            distanceMeters: Double(estimate.distanceMeters),
            objectCoordinate: .init(latitude: objectCoordinate.latitude, longitude: objectCoordinate.longitude),
            phoneCoordinate: .init(latitude: sensor.coordinate.latitude, longitude: sensor.coordinate.longitude),
            phoneHorizontalAccuracyMeters: sensor.horizontalAccuracyMeters,
            phoneAltitudeMeters: sensor.altitudeMeters,
            headingDegrees: sensor.headingDegrees,
            headingAccuracyDegrees: sensor.headingAccuracyDegrees,
            relativeAltitudeMeters: sensor.relativeAltitudeMeters,
            pressureKilopascals: sensor.pressureKilopascals,
            movement: movement
        )
    }

    private func matchedTrack(
        objectType: DetectableObjectType,
        boundingBox: CGRect,
        objectCoordinate: CLLocationCoordinate2D,
        now: Date
    ) -> ActiveTrack {
        if let index = activeTracks.firstIndex(where: {
            $0.objectType == objectType && Self.iou($0.boundingBox, boundingBox) >= trackMatchIoU
        }) {
            return activeTracks[index]
        }

        let track = ActiveTrack(
            id: UUID(),
            objectType: objectType,
            boundingBox: boundingBox,
            lastLoggedAt: .distantPast,
            lastCoordinate: objectCoordinate
        )
        activeTracks.append(track)
        return track
    }

    private func updateTrack(
        id: UUID,
        objectType: DetectableObjectType,
        boundingBox: CGRect,
        coordinate: CLLocationCoordinate2D,
        now: Date
    ) {
        guard let index = activeTracks.firstIndex(where: { $0.id == id }) else { return }
        activeTracks[index] = ActiveTrack(
            id: id,
            objectType: objectType,
            boundingBox: boundingBox,
            lastLoggedAt: now,
            lastCoordinate: coordinate
        )
    }

    private func movementEntry(
        from previous: CLLocationCoordinate2D,
        to current: CLLocationCoordinate2D,
        elapsed: TimeInterval
    ) -> ObjectTrackLogEntry.Movement? {
        guard elapsed.isFinite, elapsed > 0, elapsed < 60 else { return nil }

        let distance = Self.distanceMeters(from: previous, to: current)
        let bearing = Self.bearingDegrees(from: previous, to: current)
        let speed = distance / elapsed
        let predicted = Self.destinationCoordinate(
            from: current,
            distanceMeters: speed * minimumLogInterval,
            bearingDegrees: bearing
        )

        return ObjectTrackLogEntry.Movement(
            distanceFromPreviousMeters: distance,
            bearingFromPreviousDegrees: bearing,
            speedMetersPerSecond: speed,
            predictedLatitude: predicted.latitude,
            predictedLongitude: predicted.longitude
        )
    }

    private func append(_ entry: ObjectTrackLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxVisibleEntries {
            entries.removeLast(entries.count - maxVisibleEntries)
        }

        guard let data = try? encoder.encode(entry) else { return }
        var line = data
        line.append(0x0A)

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    private func loadRecentEntries() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        entries = Array(lines.suffix(maxVisibleEntries).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ObjectTrackLogEntry.self, from: data)
        }
        .reversed())
    }

    private func objectBearingDegrees(
        phoneHeadingDegrees: Double,
        boundingBox: CGRect,
        horizontalFOV: CGFloat
    ) -> Double {
        let centerOffset = Double(boundingBox.midX - 0.5)
        let angleOffset = atan(centerOffset * 2 * Double(tan(horizontalFOV / 2))) * 180 / .pi
        return Self.normalizedDegrees(phoneHeadingDegrees + angleOffset)
    }

    private static func iou(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private static func destinationCoordinate(
        from start: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distanceMeters / earthRadius
        let bearing = bearingDegrees * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: normalizedLongitude(lon2 * 180 / .pi)
        )
    }

    private static func distanceMeters(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return startLocation.distance(from: endLocation)
    }

    private static func bearingDegrees(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalizedDegrees(atan2(y, x) * 180 / .pi)
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        ((longitude + 540).truncatingRemainder(dividingBy: 360)) - 180
    }
}
