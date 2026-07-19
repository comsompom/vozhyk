import SwiftUI

struct DetectionOverlayView: View {
    let detections: [VisionDetection]
    /// Aspect ratio of the camera buffer that Vision used for these detections.
    let videoAspectRatio: CGFloat
    let cameraHorizontalFieldOfViewDegrees: CGFloat
    let cameraZoomFactor: CGFloat
    @ObservedObject var settings: DetectionSettingsStore

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
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

                if let estimate = DistanceEstimator.nearestEstimate(
                    in: detections,
                    enabledTypes: settings.distanceEnabledTypes,
                    frameAspectRatio: videoAspectRatio,
                    horizontalFieldOfViewDegrees: cameraHorizontalFieldOfViewDegrees,
                    zoomFactor: cameraZoomFactor
                   ) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(estimate.objectTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(estimate.formattedDistance)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.35), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 56)
                    .padding(.trailing, 12)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }

    private func convert(_ box: CGRect, in size: CGSize) -> CGRect {
        // AVCaptureVideoPreviewLayer uses resizeAspectFill. Apply the exact same
        // scale and crop here; mapping normalized Vision coordinates directly to the
        // screen shifts boxes whenever the preview crops the camera image.
        let sourceWidth = videoAspectRatio
        let sourceHeight: CGFloat = 1
        let scale = max(size.width / sourceWidth, size.height / sourceHeight)
        let renderedWidth = sourceWidth * scale
        let renderedHeight = sourceHeight * scale
        let cropX = (renderedWidth - size.width) / 2
        let cropY = (renderedHeight - size.height) / 2

        return CGRect(
            x: box.minX * renderedWidth - cropX,
            y: (1 - box.maxY) * renderedHeight - cropY,
            width: box.width * renderedWidth,
            height: box.height * renderedHeight
        )
    }
}

private struct DistanceEstimate {
    let objectTitle: String
    let distanceMeters: CGFloat

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

private enum DistanceEstimator {
    static func nearestEstimate(
        in detections: [VisionDetection],
        enabledTypes: Set<DetectableObjectType>,
        frameAspectRatio: CGFloat,
        horizontalFieldOfViewDegrees: CGFloat,
        zoomFactor: CGFloat
    ) -> DistanceEstimate? {
        guard !enabledTypes.isEmpty else { return nil }

        let axisFOV = effectiveAxisFieldOfViews(
            frameAspectRatio: frameAspectRatio,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            zoomFactor: zoomFactor
        )

        return detections
            .filter { enabledTypes.contains($0.objectType) }
            .compactMap { estimate(for: $0, horizontalFOV: axisFOV.horizontal, verticalFOV: axisFOV.vertical) }
            .min { $0.distanceMeters < $1.distanceMeters }
    }

    private static func estimate(
        for detection: VisionDetection,
        horizontalFOV: CGFloat,
        verticalFOV: CGFloat
    ) -> DistanceEstimate? {
        switch detection.objectType {
        case .human:
            return distance(
                title: detection.objectType.title,
                realMeters: 1.75,
                normalizedSpan: detection.boundingBox.height,
                fieldOfViewRadians: verticalFOV
            )
        case .auto:
            let majorSpan = max(detection.boundingBox.width, detection.boundingBox.height)
            let majorFOV = detection.boundingBox.width >= detection.boundingBox.height ? horizontalFOV : verticalFOV
            return distance(
                title: detection.objectType.title,
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
            return DistanceEstimate(
                objectTitle: detection.objectType.title,
                distanceMeters: values.reduce(0, +) / CGFloat(values.count)
            )
        case .plane, .drone, .bird, .bus, .truck, .motorcycle:
            return nil
        }
    }

    private static func distance(
        title: String,
        realMeters: CGFloat,
        normalizedSpan: CGFloat,
        fieldOfViewRadians: CGFloat
    ) -> DistanceEstimate? {
        guard let meters = distanceMeters(
            realMeters: realMeters,
            normalizedSpan: normalizedSpan,
            fieldOfViewRadians: fieldOfViewRadians
        ) else { return nil }

        return DistanceEstimate(objectTitle: title, distanceMeters: meters)
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

    private static func effectiveAxisFieldOfViews(
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
    let cameraZoomFactor: CGFloat

    @State private var selectedPanel: HUDPanel? = nil

    private enum HUDPanel: CaseIterable, Identifiable {
        case threat
        case camera
        case radio
        case model
        case visual

        var id: Self { self }
    }

    var body: some View {
        ZStack {
            HStack {
                VStack(spacing: 10) {
                    ForEach(HUDPanel.allCases) { panel in
                        railButton(for: panel)
                    }
                }
                .padding(.leading, 10)
                .padding(.top, 64)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let selectedPanel {
                VStack {
                    Spacer()
                    detailPanel(for: selectedPanel)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPanel)
    }

    @ViewBuilder
    private func detailPanel(for panel: HUDPanel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(panelTitle(for: panel), systemImage: panelIcon(for: panel))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(panelColor(for: panel))
                Spacer()
                Button {
                    selectedPanel = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }

            panelContent(for: panel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(panelColor(for: panel).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func panelContent(for panel: HUDPanel) -> some View {
        switch panel {
        case .threat:
            Text(threatLevel.title)
                .font(.callout.weight(.semibold))
            Text("Camera and radio statuses are combined into the current threat level.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .camera:
            Text(cameraActive ? "Camera ON" : "Camera OFF")
                .font(.callout.weight(.semibold))
            Text("Auto zoom: \(formattedZoomFactor)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(cameraZoomFactor > 1.01 ? .cyan : .secondary)
            Text(cameraActive ? "Visual detection is receiving camera frames." : "Camera scanning is paused or unavailable.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .radio:
            if !radioSignals.isEmpty {
                ForEach(radioSignals.prefix(4)) { signal in
                    HStack {
                        Image(systemName: signal.band.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(signal.name)
                                .font(.caption.weight(.semibold))
                            Text("\(signal.matchedProfile) - \(signal.band.rawValue) - \(signal.rssi) dBm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                Text(radioScanning ? radioStatus : "RF Scan OFF")
                    .font(.callout.weight(.semibold))
                Text("Scanning BLE 2.4 GHz and checking Wi-Fi drone SSID patterns.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .model:
            Text(modelLoaded ? "AI Model Ready" : "AI Model Missing")
                .font(.callout.weight(.semibold))
            Text("AI: \(modelName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let modelLoadError {
                Text(modelLoadError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        case .visual:
            if cameraDetections.isEmpty {
                Text("No visual objects detected")
                    .font(.callout.weight(.semibold))
                Text("Detected objects will appear here while scanning.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cameraDetections) { detection in
                    Text("\(detection.label) - \(Int(detection.confidence * 100))% (\(detection.source.rawValue))")
                        .font(.caption)
                }
            }
        }
    }

    private func railButton(for panel: HUDPanel) -> some View {
        let isSelected = selectedPanel == panel
        let color = panelColor(for: panel)

        return Button {
            selectedPanel = isSelected ? nil : panel
        } label: {
            Image(systemName: panelIcon(for: panel))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(color.opacity(isSelected ? 0.34 : 0.22))
                .foregroundStyle(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(isSelected ? 0.85 : 0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panelTitle(for: panel))
    }

    private func panelTitle(for panel: HUDPanel) -> String {
        switch panel {
        case .threat: return threatLevel.title
        case .camera: return cameraActive ? "Camera ON" : "Camera OFF"
        case .radio:
            if !radioSignals.isEmpty { return "Radio Drone Waves Detected" }
            return radioScanning ? "RF Scan ON" : "RF Scan OFF"
        case .model: return modelLoaded ? "AI Model Ready" : "AI Model Missing"
        case .visual: return "Visual Detection"
        }
    }

    private func panelIcon(for panel: HUDPanel) -> String {
        switch panel {
        case .threat:
            return threatLevel == .clear ? "checkmark.shield" : "exclamationmark.triangle.fill"
        case .camera:
            return "camera.fill"
        case .radio:
            return "antenna.radiowaves.left.and.right"
        case .model:
            return modelLoaded ? "brain.head.profile" : "exclamationmark.circle"
        case .visual:
            return "scope"
        }
    }

    private func panelColor(for panel: HUDPanel) -> Color {
        switch panel {
        case .threat:
            return color(for: threatLevel)
        case .camera:
            return cameraActive ? .green : .gray
        case .radio:
            if !radioSignals.isEmpty { return .orange }
            return radioScanning ? .cyan : .gray
        case .model:
            return modelLoaded ? .mint : .orange
        case .visual:
            return cameraDetections.isEmpty ? .gray : .green
        }
    }

    private func color(for level: ThreatLevel) -> Color {
        switch level {
        case .clear: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    private var formattedZoomFactor: String {
        let rounded = (cameraZoomFactor * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))x"
        }
        return String(format: "%.1fx", rounded)
    }
}
