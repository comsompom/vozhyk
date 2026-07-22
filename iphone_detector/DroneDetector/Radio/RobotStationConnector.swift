import Foundation
import SwiftUI
import UIKit

@MainActor
final class RobotStationConnector: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected

        var title: String {
            switch self {
            case .disconnected: return "Robot disconnected"
            case .connecting: return "Robot connecting"
            case .connected: return "Robot connected"
            }
        }

        var color: Color {
            switch self {
            case .disconnected: return .red
            case .connecting: return .yellow
            case .connected: return .green
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var statusMessage = "Robot station not connected"

    private struct TargetPayload: Encodable {
        let device: String
        let objectName: String
        let screenX: Double
        let screenY: Double
        let latitude: Double
        let longitude: Double
        let altitudeMeters: Double
        let distanceMeters: Double
        let confidence: Float
        let phoneLatitude: Double
        let phoneLongitude: Double
        let phoneAltitudeMeters: Double?
        let bearingDegrees: Double

        enum CodingKeys: String, CodingKey {
            case device
            case objectName = "object_name"
            case screenX = "screen_x"
            case screenY = "screen_y"
            case latitude
            case longitude
            case altitudeMeters = "altitude_m"
            case distanceMeters = "distance_m"
            case confidence
            case phoneLatitude = "phone_latitude"
            case phoneLongitude = "phone_longitude"
            case phoneAltitudeMeters = "phone_altitude_m"
            case bearingDegrees = "bearing_degrees"
        }
    }

    private let connectEndpoint = URL(string: "http://192.168.4.1/iphone/connect")!
    private let targetEndpoint = URL(string: "http://192.168.4.1/target")!
    private let timeout: TimeInterval = 4
    private let targetSendInterval: TimeInterval = 1.0
    private var lastTargetSentAt = Date.distantPast

    func connect() {
        guard state != .connecting else { return }
        state = .connecting
        statusMessage = "Connecting to ESP32 robot station..."

        Task {
            await connectToRobotStation()
        }
    }

    func sendAutoHumanTargets(
        detections: [VisionDetection],
        sensor: SensorSnapshot?,
        frameAspectRatio: CGFloat,
        horizontalFieldOfViewDegrees: CGFloat,
        zoomFactor: CGFloat
    ) {
        guard state == .connected, let sensor else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTargetSentAt) >= targetSendInterval else { return }

        let estimates = ObjectPositionEstimator.estimates(
            in: detections,
            enabledTypes: [.auto, .human],
            sensor: sensor,
            frameAspectRatio: frameAspectRatio,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            zoomFactor: zoomFactor
        )

        guard !estimates.isEmpty else { return }
        lastTargetSentAt = now

        for estimate in estimates {
            Task {
                await sendTarget(estimate, sensor: sensor)
            }
        }
    }

    private func connectToRobotStation() async {
        var request = URLRequest(url: connectEndpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceName = UIDevice.current.name
        let payload: [String: String] = ["device": deviceName]

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                state = .disconnected
                statusMessage = "ESP32 rejected connection"
                return
            }

            state = .connected
            statusMessage = "Connected to ESP32 robot station"
        } catch {
            state = .disconnected
            statusMessage = "ESP32 connection failed. Join Vozhyk-Robot Wi-Fi first."
        }
    }

    private func sendTarget(_ estimate: ObjectPositionEstimate, sensor: SensorSnapshot) async {
        var request = URLRequest(url: targetEndpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let altitude = sensor.altitudeMeters ?? sensor.relativeAltitudeMeters ?? 0
        let payload = TargetPayload(
            device: UIDevice.current.name,
            objectName: estimate.detection.objectType.rawValue,
            screenX: estimate.screenX,
            screenY: estimate.screenY,
            latitude: estimate.coordinate.latitude,
            longitude: estimate.coordinate.longitude,
            altitudeMeters: altitude,
            distanceMeters: estimate.distanceMeters,
            confidence: estimate.detection.confidence,
            phoneLatitude: sensor.coordinate.latitude,
            phoneLongitude: sensor.coordinate.longitude,
            phoneAltitudeMeters: sensor.altitudeMeters,
            bearingDegrees: estimate.bearingDegrees
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                statusMessage = "ESP32 target send rejected"
                return
            }
            statusMessage = "Sent \(estimate.detection.objectType.title) target to ESP32"
        } catch {
            state = .disconnected
            statusMessage = "ESP32 target send failed"
        }
    }
}
