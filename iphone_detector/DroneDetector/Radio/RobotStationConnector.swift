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

    private let endpoint = URL(string: "http://192.168.4.1/iphone/connect")!
    private let timeout: TimeInterval = 4

    func connect() {
        guard state != .connecting else { return }
        state = .connecting
        statusMessage = "Connecting to ESP32 robot station..."

        Task {
            await connectToRobotStation()
        }
    }

    private func connectToRobotStation() async {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
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
}
