import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: DetectionSettingsStore
    @ObservedObject var trackLogger: ObjectTrackLogger
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView {
                detectionTab
                    .tabItem {
                        Label("Detection", systemImage: "scope")
                    }

                trackLogTab
                    .tabItem {
                        Label("Tracks", systemImage: "map")
                    }

                aboutTab
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var detectionTab: some View {
        List {
            Section("Objects to detect") {
                ForEach(DetectableObjectType.allCases) { type in
                    Toggle(type.title, isOn: Binding(
                        get: { settings.isEnabled(type) },
                        set: { settings.setEnabled($0, for: type) }
                    ))
                }
            }

            Section("Distance") {
                ForEach(DetectionSettingsStore.distanceObjectTypes) { type in
                    Toggle(type.title, isOn: Binding(
                        get: { settings.isDistanceEnabled(type) },
                        set: { settings.setDistanceEnabled($0, for: type) }
                    ))
                }
            }

            Section("Track logging") {
                ForEach(DetectionSettingsStore.trackObjectTypes) { type in
                    Toggle(type.title, isOn: Binding(
                        get: { settings.isTrackEnabled(type) },
                        set: { settings.setTrackEnabled($0, for: type) }
                    ))
                }
            }

            Section("Border colors") {
                ForEach(DetectableObjectType.allCases) { type in
                    HStack {
                        Text(type.title)
                        Spacer()
                        Menu {
                            ForEach(BorderColorOption.allCases) { option in
                                Button {
                                    settings.setBorderColor(option, for: type)
                                } label: {
                                    Label(option.title, systemImage: "circle.fill")
                                        .foregroundStyle(option.color)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(settings.borderColor(for: type))
                                    .frame(width: 14, height: 14)
                                Text(settings.borderColorByType[type, default: type.defaultBorderColor].title)
                            }
                        }
                    }
                }
            }
        }
    }

    private var trackLogTab: some View {
        List {
            Section("Tracking") {
                ForEach(DetectionSettingsStore.trackObjectTypes) { type in
                    Toggle(type.title, isOn: Binding(
                        get: { settings.isTrackEnabled(type) },
                        set: { settings.setTrackEnabled($0, for: type) }
                    ))
                }

                LabeledContent("Status", value: trackLogger.statusMessage)
                LabeledContent("Log file", value: trackLogger.logFilePath)
                    .font(.caption)
            }

            Section {
                Button(role: .destructive) {
                    trackLogger.clearLogs()
                } label: {
                    Label("Clear Track Logs", systemImage: "trash")
                }
                .disabled(trackLogger.entries.isEmpty)
            }

            Section("Recent logs") {
                if trackLogger.entries.isEmpty {
                    Text("No object tracks saved yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trackLogger.entries) { entry in
                        trackLogRow(entry)
                    }
                }
            }
        }
    }

    private func trackLogRow(_ entry: ObjectTrackLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.objectTitle)
                    .font(.headline)
                Spacer()
                Text(Self.timeFormatter.string(from: entry.detectedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(String(
                format: "Object %.6f, %.6f - %.1f m - %.0f%%",
                entry.objectCoordinate.latitude,
                entry.objectCoordinate.longitude,
                entry.distanceMeters,
                entry.confidence * 100
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if let movement = entry.movement {
                Text(String(
                    format: "Track %.1f m @ %.0f deg - %.1f m/s - next %.6f, %.6f",
                    movement.distanceFromPreviousMeters,
                    movement.bearingFromPreviousDegrees,
                    movement.speedMetersPerSecond,
                    movement.predictedLatitude,
                    movement.predictedLongitude
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var aboutTab: some View {
        List {
            Section("Vozhyk Drone Detector") {
                LabeledContent("Version", value: appVersion)
                Text("On-device drone monitoring using camera AI and local radio signature analysis. Works offline after installation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
