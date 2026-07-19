import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionDetector = DroneVisionDetector()
    @StateObject private var radioScanner = RadioScanner()
    @StateObject private var locationManager = LocationPermissionManager()
    @StateObject private var detectionSettings = DetectionSettingsStore()

    @State private var isScanning = false
    @State private var showSettings = false

    private var scannerState: ScannerState {
        ScannerState(
            isCameraActive: cameraManager.isRunning,
            isRadioScanning: radioScanner.isScanning,
            cameraDetections: visionDetector.detections,
            radioSignals: radioScanner.signals,
            lastCameraDetection: visionDetector.detections.isEmpty ? nil : Date(),
            errorMessage: cameraManager.errorMessage
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraManager.authorizationStatus == .authorized || cameraManager.authorizationStatus == .notDetermined {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()

                DetectionOverlayView(
                    detections: visionDetector.detections,
                    videoAspectRatio: visionDetector.frameAspectRatio,
                    cameraHorizontalFieldOfViewDegrees: cameraManager.horizontalFieldOfViewDegrees,
                    cameraZoomFactor: cameraManager.currentZoomFactor,
                    settings: detectionSettings
                )
                    .ignoresSafeArea()
            } else {
                permissionView
            }

            StatusHUDView(
                threatLevel: scannerState.threatLevel,
                cameraActive: cameraManager.isRunning,
                radioScanning: radioScanner.isScanning,
                cameraDetections: visionDetector.detections,
                radioSignals: radioScanner.signals,
                modelName: visionDetector.modelName,
                modelLoaded: visionDetector.isModelLoaded,
                modelLoadError: visionDetector.loadError,
                radioStatus: radioScanner.statusMessage,
                cameraZoomFactor: cameraManager.currentZoomFactor
            )

            VStack {
                Spacer()
                controlBar
            }
        }
        .onAppear {
            wireCameraPipeline()
            visionDetector.updateEnabledTypes(detectionSettings.enabledTypes)
            startScanning()
        }
        .onDisappear {
            stopScanning()
        }
        .onChange(of: detectionSettings.enabledByType) { _ in
            visionDetector.updateEnabledTypes(detectionSettings.enabledTypes)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: detectionSettings)
        }
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text("Camera Access Required")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("DroneDetector needs the rear camera to visually track drones in the sky.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button {
                isScanning ? stopScanning() : startScanning()
            } label: {
                Label(isScanning ? "Stop" : "Start", systemImage: isScanning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isScanning ? .red : .green)
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    private func wireCameraPipeline() {
        // Process on the camera/video queue — do NOT hop to MainActor first
        // (that was causing 1–2s lag before the box appeared).
        cameraManager.setFrameHandler { [weak visionDetector] sampleBuffer in
            visionDetector?.process(sampleBuffer: sampleBuffer)
        }
    }

    private func startScanning() {
        isScanning = true
        locationManager.requestWhenInUse()
        cameraManager.requestAccessAndStart()
        radioScanner.start()
    }

    private func stopScanning() {
        isScanning = false
        cameraManager.stop()
        radioScanner.stop()
    }
}

#Preview {
    ContentView()
}
