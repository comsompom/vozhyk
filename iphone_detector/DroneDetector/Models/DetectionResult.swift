import CoreGraphics
import Foundation

struct VisionDetection: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let source: DetectionSource
}

enum DetectionSource: String {
    case vision = "Camera AI"
    case motion = "Motion"
}

struct RadioSignal: Identifiable, Equatable {
    let id: String
    let name: String
    let rssi: Int
    let band: RadioBand
    let matchedProfile: String
    let lastSeen: Date
}

enum RadioBand: String, CaseIterable {
    case ble = "BLE 2.4 GHz"
    case wifi = "Wi-Fi 2.4/5 GHz"

    var icon: String {
        switch self {
        case .ble: return "dot.radiowaves.left.and.right"
        case .wifi: return "wifi"
        }
    }
}

struct ScannerState {
    var isCameraActive = false
    var isRadioScanning = false
    var cameraDetections: [VisionDetection] = []
    var radioSignals: [RadioSignal] = []
    var lastCameraDetection: Date?
    var errorMessage: String?
}

extension ScannerState {
    var hasCameraDetection: Bool {
        !cameraDetections.isEmpty
    }

    var hasRadioDetection: Bool {
        !radioSignals.isEmpty
    }

    var threatLevel: ThreatLevel {
        if hasCameraDetection && hasRadioDetection { return .high }
        if hasCameraDetection || hasRadioDetection { return .medium }
        return .clear
    }
}

enum ThreatLevel {
    case clear
    case medium
    case high

    var title: String {
        switch self {
        case .clear: return "CLEAR"
        case .medium: return "POSSIBLE DRONE"
        case .high: return "DRONE DETECTED"
        }
    }

    var colorName: String {
        switch self {
        case .clear: return "StatusClear"
        case .medium: return "StatusWarning"
        case .high: return "StatusAlert"
        }
    }
}
