import SwiftUI
import Foundation

enum DetectableObjectType: String, CaseIterable, Codable, Identifiable, Equatable, Hashable {
    case auto
    case plane
    case drone
    case planeDrone = "plane_drone"
    case bird
    case human
    case bus
    case truck
    case motorcycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .plane: return "Plane"
        case .drone: return "Drone"
        case .planeDrone: return "Plane Drone"
        case .bird: return "Bird"
        case .human: return "Human"
        case .bus: return "Bus"
        case .truck: return "Truck"
        case .motorcycle: return "Motorcycle"
        }
    }

    var defaultBorderColor: BorderColorOption {
        switch self {
        case .drone, .planeDrone:
            return .red
        default:
            return .green
        }
    }
}

enum BorderColorOption: String, CaseIterable, Codable, Identifiable, Equatable, Hashable {
    case green, cyan, blue, yellow, orange, red, pink, white

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .green: return .green
        case .cyan: return .cyan
        case .blue: return .blue
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .white: return .white
        }
    }
}

private struct DetectionSettingsPayload: Codable {
    let enabled: [String: Bool]
    let borderColors: [String: String]
    let showDistanceEstimates: Bool?
    let distanceEnabled: [String: Bool]?
    let trackEnabled: [String: Bool]?
}

@MainActor
final class DetectionSettingsStore: ObservableObject {
    @Published var enabledByType: [DetectableObjectType: Bool]
    @Published var borderColorByType: [DetectableObjectType: BorderColorOption]
    @Published var showDistanceEstimates: Bool
    @Published var distanceEnabledByType: [DetectableObjectType: Bool]
    @Published var trackEnabledByType: [DetectableObjectType: Bool]

    private let defaults = UserDefaults.standard
    private let storageKey = "vozhyk.detection.settings.v1"
    private let droneColorMigrationKey = "vozhyk.detection.settings.droneRedDefault.v1"

    init() {
        let defaultEnabled = Dictionary(uniqueKeysWithValues: DetectableObjectType.allCases.map { ($0, true) })
        let defaultColors = Dictionary(uniqueKeysWithValues: DetectableObjectType.allCases.map { ($0, $0.defaultBorderColor) })
        let defaultDistanceEnabled = Dictionary(uniqueKeysWithValues: Self.distanceObjectTypes.map { ($0, false) })
        let defaultTrackEnabled = Dictionary(uniqueKeysWithValues: Self.trackObjectTypes.map { ($0, false) })

        if let data = defaults.data(forKey: storageKey),
           let payload = try? JSONDecoder().decode(DetectionSettingsPayload.self, from: data) {
            var mergedEnabled = defaultEnabled
            var mergedColors = defaultColors
            var mergedDistanceEnabled = defaultDistanceEnabled
            var mergedTrackEnabled = defaultTrackEnabled

            for type in DetectableObjectType.allCases {
                if let value = payload.enabled[type.rawValue] {
                    mergedEnabled[type] = value
                }
                if let rawColor = payload.borderColors[type.rawValue],
                   let color = BorderColorOption(rawValue: rawColor) {
                    mergedColors[type] = color
                }
            }

            if let distanceEnabled = payload.distanceEnabled {
                for type in Self.distanceObjectTypes {
                    if let value = distanceEnabled[type.rawValue] {
                        mergedDistanceEnabled[type] = value
                    }
                }
            } else if payload.showDistanceEstimates == true {
                for type in Self.distanceObjectTypes {
                    mergedDistanceEnabled[type] = true
                }
            }

            if let trackEnabled = payload.trackEnabled {
                for type in Self.trackObjectTypes {
                    if let value = trackEnabled[type.rawValue] {
                        mergedTrackEnabled[type] = value
                    }
                }
            }

            self.enabledByType = mergedEnabled
            self.borderColorByType = mergedColors
            self.distanceEnabledByType = mergedDistanceEnabled
            self.showDistanceEstimates = mergedDistanceEnabled.contains { $0.value }
            self.trackEnabledByType = mergedTrackEnabled
            migrateDroneDefaultColorsIfNeeded()
        } else {
            self.enabledByType = defaultEnabled
            self.borderColorByType = defaultColors
            self.distanceEnabledByType = defaultDistanceEnabled
            self.showDistanceEstimates = false
            self.trackEnabledByType = defaultTrackEnabled
        }
    }

    static let distanceObjectTypes: [DetectableObjectType] = [.auto, .human, .planeDrone, .drone]
    static let trackObjectTypes: [DetectableObjectType] = [.auto, .planeDrone, .drone]

    var enabledTypes: Set<DetectableObjectType> {
        Set(enabledByType.compactMap { $0.value ? $0.key : nil })
    }

    var distanceEnabledTypes: Set<DetectableObjectType> {
        Set(distanceEnabledByType.compactMap { $0.value ? $0.key : nil })
    }

    var trackEnabledTypes: Set<DetectableObjectType> {
        Set(trackEnabledByType.compactMap { $0.value ? $0.key : nil })
    }

    func isEnabled(_ type: DetectableObjectType) -> Bool {
        enabledByType[type] ?? true
    }

    func borderColor(for type: DetectableObjectType) -> Color {
        (borderColorByType[type] ?? type.defaultBorderColor).color
    }

    func isDistanceEnabled(_ type: DetectableObjectType) -> Bool {
        distanceEnabledByType[type] ?? false
    }

    func isTrackEnabled(_ type: DetectableObjectType) -> Bool {
        trackEnabledByType[type] ?? false
    }

    func setEnabled(_ enabled: Bool, for type: DetectableObjectType) {
        enabledByType[type] = enabled
        save()
    }

    func setBorderColor(_ color: BorderColorOption, for type: DetectableObjectType) {
        borderColorByType[type] = color
        save()
    }

    func setShowDistanceEstimates(_ enabled: Bool) {
        showDistanceEstimates = enabled
        for type in Self.distanceObjectTypes {
            distanceEnabledByType[type] = enabled
        }
        save()
    }

    func setDistanceEnabled(_ enabled: Bool, for type: DetectableObjectType) {
        guard Self.distanceObjectTypes.contains(type) else { return }
        distanceEnabledByType[type] = enabled
        showDistanceEstimates = distanceEnabledByType.contains { $0.value }
        save()
    }

    func setTrackEnabled(_ enabled: Bool, for type: DetectableObjectType) {
        guard Self.trackObjectTypes.contains(type) else { return }
        trackEnabledByType[type] = enabled
        save()
    }

    private func save() {
        let payload = DetectionSettingsPayload(
            enabled: Dictionary(uniqueKeysWithValues: enabledByType.map { ($0.key.rawValue, $0.value) }),
            borderColors: Dictionary(uniqueKeysWithValues: borderColorByType.map { ($0.key.rawValue, $0.value.rawValue) }),
            showDistanceEstimates: showDistanceEstimates,
            distanceEnabled: Dictionary(uniqueKeysWithValues: distanceEnabledByType.map { ($0.key.rawValue, $0.value) }),
            trackEnabled: Dictionary(uniqueKeysWithValues: trackEnabledByType.map { ($0.key.rawValue, $0.value) })
        )

        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func migrateDroneDefaultColorsIfNeeded() {
        guard !defaults.bool(forKey: droneColorMigrationKey) else { return }

        var changed = false
        for type in [DetectableObjectType.drone, .planeDrone] {
            if borderColorByType[type] == .green {
                borderColorByType[type] = type.defaultBorderColor
                changed = true
            }
        }

        defaults.set(true, forKey: droneColorMigrationKey)
        if changed {
            save()
        }
    }
}
