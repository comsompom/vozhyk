import SwiftUI

struct DetectionOverlayView: View {
    let detections: [VisionDetection]
    @ObservedObject var settings: DetectionSettingsStore

    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let rect = convert(detection.boundingBox, in: geometry.size)
                ZStack(alignment: .topLeading) {
                    let borderColor = settings.borderColor(for: detection.objectType)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(borderColor.opacity(0.85))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: rect.midX, y: max(12, rect.minY - 10))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func convert(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}

struct StatusHUDView: View {
    let threatLevel: ThreatLevel
    let cameraActive: Bool
    let radioScanning: Bool
    let cameraDetections: [VisionDetection]
    let radioSignals: [RadioSignal]
    let modelName: String
    let modelLoaded: Bool
    let modelLoadError: String?
    let radioStatus: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                statusPill(
                    title: threatLevel.title,
                    systemImage: threatLevel == .clear ? "checkmark.shield" : "exclamationmark.triangle.fill",
                    color: color(for: threatLevel)
                )
                Spacer()
                statusPill(
                    title: cameraActive ? "Camera ON" : "Camera OFF",
                    systemImage: "camera.fill",
                    color: cameraActive ? .green : .gray
                )
                statusPill(
                    title: radioScanning ? "RF Scan ON" : "RF Scan OFF",
                    systemImage: "antenna.radiowaves.left.and.right",
                    color: radioScanning ? .cyan : .gray
                )
            }

            statusPill(
                title: modelLoaded ? "AI Model Ready" : "AI Model Missing",
                systemImage: modelLoaded ? "brain.head.profile" : "exclamationmark.circle",
                color: modelLoaded ? .mint : .orange
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if !cameraDetections.isEmpty {
                hudCard(title: "Visual Detection", color: .green) {
                    ForEach(cameraDetections) { detection in
                        Text("\(detection.label) — \(Int(detection.confidence * 100))% (\(detection.source.rawValue))")
                            .font(.caption)
                    }
                }
            }

            if !radioSignals.isEmpty {
                hudCard(title: "Radio Drone Waves Detected", color: .orange) {
                    ForEach(radioSignals.prefix(4)) { signal in
                        HStack {
                            Image(systemName: signal.band.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.name)
                                    .font(.caption.weight(.semibold))
                                Text("\(signal.matchedProfile) • \(signal.band.rawValue) • \(signal.rssi) dBm")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } else if radioScanning {
                hudCard(title: "Radio Scanner", color: .cyan) {
                    Text(radioStatus)
                        .font(.caption)
                    Text("Scanning BLE 2.4 GHz and checking Wi-Fi drone SSID patterns.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("AI: \(modelName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let modelLoadError {
                Text(modelLoadError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    @ViewBuilder
    private func hudCard<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "dot.radiowaves.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusPill(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func color(for level: ThreatLevel) -> Color {
        switch level {
        case .clear: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}
