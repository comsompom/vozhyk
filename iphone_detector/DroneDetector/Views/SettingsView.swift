import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: DetectionSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView {
                detectionTab
                    .tabItem {
                        Label("Detection", systemImage: "scope")
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
                Toggle("Show distance estimates", isOn: Binding(
                    get: { settings.showDistanceEstimates },
                    set: { settings.setShowDistanceEstimates($0) }
                ))
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
}
