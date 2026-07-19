import AVFoundation
import Combine
import CoreMotion
import UIKit

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentZoomFactor: CGFloat = 1.0
    @Published private(set) var horizontalFieldOfViewDegrees: CGFloat = 60.0

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.vozhyk.drone-detector.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.vozhyk.drone-detector.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var isConfigured = false
    private var cameraDevice: AVCaptureDevice?
    private var stableSince: Date?
    private var lastZoomStepAt = Date.distantPast
    private var targetZoomFactor: CGFloat = 1.0
    private var smoothedRotationRate = 0.0

    private let stableDelay: TimeInterval = 1.5
    private let zoomStepInterval: TimeInterval = 1.0
    private let zoomStepFactor: CGFloat = 1.0
    private let maxAutoZoomFactor: CGFloat = 5.0
    private let stableRotationRate = 0.08
    private let movementResetRotationRate = 0.14
    nonisolated(unsafe) private var frameHandler: ((CMSampleBuffer) -> Void)?

    override init() {
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func setFrameHandler(_ handler: @escaping (CMSampleBuffer) -> Void) {
        sessionQueue.async { [weak self] in
            self?.frameHandler = handler
        }
    }

    func requestAccessAndStart() {
        switch authorizationStatus {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self?.start()
                    } else {
                        self?.errorMessage = "Camera access denied"
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Camera access denied — enable in Settings"
        @unknown default:
            errorMessage = "Unknown camera authorization state"
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
                self.startAutoZoomMonitor()
                Task { @MainActor in
                    self.isRunning = self.session.isRunning
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.stopAutoZoomMonitor()
                self.resetZoom()
                self.session.stopRunning()
                Task { @MainActor in
                    self.isRunning = false
                }
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        // 720p is enough for YOLO (640 input) and keeps latency low.
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .medium
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            Task { @MainActor in
                errorMessage = "Unable to access rear camera"
            }
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        cameraDevice = camera
        let fieldOfView = camera.activeFormat.videoFieldOfView

        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            // Prefer low-latency stream over smoothness.
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()
        } catch {
            // Continue with defaults if lock fails.
        }

        Task { @MainActor in
            self.horizontalFieldOfViewDegrees = CGFloat(fieldOfView)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Dedicated queue so camera never waits on inference.
        let videoQueue = DispatchQueue(label: "com.vozhyk.drone-detector.video-output", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(videoOutput) else {
            Task { @MainActor in
                errorMessage = "Unable to configure video output"
            }
            session.commitConfiguration()
            return
        }

        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // Stabilization adds delay — disable for tracking.
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private func startAutoZoomMonitor() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        stableSince = nil
        lastZoomStepAt = .distantPast
        smoothedRotationRate = 0
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.sessionQueue.async { [weak self] in
                self?.handleDeviceMotion(motion)
            }
        }
    }

    private func stopAutoZoomMonitor() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        stableSince = nil
        lastZoomStepAt = .distantPast
        smoothedRotationRate = 0
    }

    private func handleDeviceMotion(_ motion: CMDeviceMotion) {
        let rate = motion.rotationRate
        let rotationMagnitude = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z)
        smoothedRotationRate = smoothedRotationRate * 0.7 + rotationMagnitude * 0.3

        let now = Date()
        if smoothedRotationRate >= movementResetRotationRate {
            stableSince = nil
            lastZoomStepAt = .distantPast
            resetZoom()
            return
        }

        guard smoothedRotationRate <= stableRotationRate else {
            stableSince = nil
            return
        }

        if stableSince == nil {
            stableSince = now
            return
        }

        guard let stableSince,
              now.timeIntervalSince(stableSince) >= stableDelay,
              now.timeIntervalSince(lastZoomStepAt) >= zoomStepInterval else { return }

        lastZoomStepAt = now
        applyZoom(targetZoomFactor + zoomStepFactor, ramp: true)
    }

    private func resetZoom() {
        applyZoom(1.0, ramp: true)
    }

    private func applyZoom(_ requestedFactor: CGFloat, ramp: Bool) {
        guard let camera = cameraDevice else { return }
        let maxSupportedZoom = min(maxAutoZoomFactor, camera.activeFormat.videoMaxZoomFactor)
        let nextZoom = min(max(requestedFactor, 1.0), maxSupportedZoom)
        guard abs(nextZoom - targetZoomFactor) > 0.01 else { return }

        do {
            try camera.lockForConfiguration()
            if camera.isRampingVideoZoom {
                camera.cancelVideoZoomRamp()
            }
            if ramp {
                camera.ramp(toVideoZoomFactor: nextZoom, withRate: 4.0)
            } else {
                camera.videoZoomFactor = nextZoom
            }
            camera.unlockForConfiguration()
            targetZoomFactor = nextZoom
            Task { @MainActor in
                self.currentZoomFactor = nextZoom
            }
        } catch {
            Task { @MainActor in
                self.errorMessage = "Unable to change camera zoom"
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameHandler?(sampleBuffer)
    }
}
