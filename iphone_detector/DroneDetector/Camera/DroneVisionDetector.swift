import AVFoundation
import CoreML
import Foundation
import Vision

final class DroneVisionDetector: ObservableObject {
    @Published private(set) var detections: [VisionDetection] = []
    @Published private(set) var isModelLoaded = false
    @Published private(set) var modelName = "Motion + Aerial Heuristics"
    @Published private(set) var loadError: String?

    private var visionModel: VNCoreMLModel?
    private var request: VNCoreMLRequest?

    private let inferenceQueue = DispatchQueue(
        label: "com.vozhyk.drone-detector.inference",
        qos: .userInitiated
    )
    private let stateQueue = DispatchQueue(label: "com.vozhyk.drone-detector.vision-state")

    private var isYOLOBusy = false
    private var previousLumaGrid: [Float]?
    private var lastMotionPublish = Date.distantPast
    private var lastDetectionPublish = Date.distantPast
    private let confidenceThreshold: Float = 0.20
    private let maxDetectionAge: TimeInterval = 0.25
    private let motionGrid = 16

    private static let cocoClassNames: [String] = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
        "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
        "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]

    private let aerialLabels: Set<String> = [
        "airplane", "aircraft", "bird", "kite", "drone", "uav", "quadcopter", "flying"
    ]

    init() {
        loadModel()
    }

    /// Called from the camera video queue. Keeps the green box near realtime.
    nonisolated func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // --- Fast path: motion tracking every frame (does not wait for YOLO) ---
        let motionUpdate: [VisionDetection]? = stateQueue.sync {
            let motion = runMotionHeuristic(current: pixelBuffer)
            guard !motion.isEmpty else { return nil }
            let now = Date()
            guard now.timeIntervalSince(lastMotionPublish) > 0.03 else { return nil }
            lastMotionPublish = now
            return motion
        }

        if let motionUpdate {
            DispatchQueue.main.async { [weak self] in
                self?.publish(motionUpdate, preferOverExistingYOLO: false)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.clearIfStale()
            }
        }

        // --- Slow path: YOLO when free; drops frames instead of queueing lag ---
        let shouldRunYOLO = stateQueue.sync { () -> Bool in
            guard request != nil, !isYOLOBusy else { return false }
            isYOLOBusy = true
            return true
        }

        guard shouldRunYOLO else { return }

        // AVFoundation reuses the camera buffer after this callback returns —
        // copy it so YOLO can run asynchronously without stale memory.
        guard let frameCopy = Self.copyPixelBuffer(pixelBuffer) else {
            stateQueue.sync { isYOLOBusy = false }
            return
        }

        inferenceQueue.async { [weak self] in
            guard let self else { return }

            defer {
                self.stateQueue.sync { self.isYOLOBusy = false }
            }

            guard let request = self.request else { return }
            let yolo = self.runVisionRequest(request, on: frameCopy)
            guard !yolo.isEmpty else { return }

            DispatchQueue.main.async {
                self.publish(yolo, preferOverExistingYOLO: true)
            }
        }
    }

    private func publish(_ results: [VisionDetection], preferOverExistingYOLO: Bool) {
        guard !results.isEmpty else { return }

        // If we already show a YOLO box, don't let a weak motion box overwrite it
        // unless this update is also YOLO.
        if !preferOverExistingYOLO,
           detections.contains(where: { $0.source == .vision }) ,
           Date().timeIntervalSince(lastDetectionPublish) < 0.2 {
            return
        }

        lastDetectionPublish = Date()
        detections = results
    }

    private func clearIfStale() {
        if !detections.isEmpty,
           Date().timeIntervalSince(lastDetectionPublish) > maxDetectionAge {
            detections = []
        }
    }

    private func loadModel() {
        if let bundled = try? YOLOv8n(configuration: {
            let config = MLModelConfiguration()
            if #available(iOS 16.0, *) {
                config.computeUnits = .cpuAndNeuralEngine
            } else {
                config.computeUnits = .all
            }
            return config
        }()) {
            configure(with: bundled.model, displayName: "YOLOv8n Core ML")
            return
        }

        if let compiledURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlmodelc") {
            configure(withModelAt: compiledURL, displayName: "YOLOv8n Core ML")
            return
        }

        if let packageURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlpackage") {
            do {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                configure(withModelAt: compiledURL, displayName: "YOLOv8n Core ML")
            } catch {
                DispatchQueue.main.async {
                    self.loadError = "Failed to compile YOLOv8n: \(error.localizedDescription)"
                    self.modelName = "Motion fallback (model compile failed)"
                }
            }
            return
        }

        DispatchQueue.main.async {
            self.loadError = "YOLOv8n.mlpackage missing from app bundle"
            self.modelName = "Motion + Aerial Heuristics (model not in bundle)"
        }
    }

    private func configure(with model: MLModel, displayName: String) {
        do {
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill

            self.visionModel = visionModel
            self.request = request
            DispatchQueue.main.async {
                self.isModelLoaded = true
                self.loadError = nil
                self.modelName = displayName
            }
        } catch {
            DispatchQueue.main.async {
                self.loadError = error.localizedDescription
                self.modelName = "Motion fallback (model load failed)"
                self.isModelLoaded = false
            }
            visionModel = nil
            request = nil
        }
    }

    private func configure(withModelAt url: URL, displayName: String) {
        do {
            let configuration = MLModelConfiguration()
            if #available(iOS 16.0, *) {
                configuration.computeUnits = .cpuAndNeuralEngine
            } else {
                configuration.computeUnits = .all
            }
            let model = try MLModel(contentsOf: url, configuration: configuration)
            configure(with: model, displayName: displayName)
        } catch {
            DispatchQueue.main.async {
                self.loadError = error.localizedDescription
                self.modelName = "Motion fallback (model load failed)"
                self.isModelLoaded = false
            }
            visionModel = nil
            request = nil
        }
    }

    private func runVisionRequest(_ request: VNCoreMLRequest, on pixelBuffer: CVPixelBuffer) -> [VisionDetection] {
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([request])
            guard let results = request.results, !results.isEmpty else { return [] }

            if let recognized = results as? [VNRecognizedObjectObservation] {
                return mapRecognizedObjects(recognized)
            }

            return mapFeatureValueObservations(results)
        } catch {
            return []
        }
    }

    private func mapRecognizedObjects(_ observations: [VNRecognizedObjectObservation]) -> [VisionDetection] {
        observations.compactMap { observation in
            guard let top = observation.labels.first else { return nil }
            let name = top.identifier.lowercased()
            guard isAerialLabel(name), top.confidence >= confidenceThreshold else { return nil }

            return VisionDetection(
                label: displayLabel(for: name),
                confidence: top.confidence,
                boundingBox: observation.boundingBox,
                source: .vision
            )
        }
    }

    private func mapFeatureValueObservations(_ results: [Any]) -> [VisionDetection] {
        var confidenceArray: MLMultiArray?
        var coordinatesArray: MLMultiArray?

        for result in results {
            guard let feature = result as? VNCoreMLFeatureValueObservation else { continue }
            switch feature.featureName {
            case "confidence":
                confidenceArray = feature.featureValue.multiArrayValue
            case "coordinates":
                coordinatesArray = feature.featureValue.multiArrayValue
            default:
                break
            }
        }

        guard let confidence = confidenceArray, let coordinates = coordinatesArray else {
            return []
        }

        let boxCount = confidence.shape[0].intValue
        let classCount = confidence.shape.count > 1 ? confidence.shape[1].intValue : 0
        guard boxCount > 0, classCount > 0, coordinates.shape[0].intValue == boxCount else {
            return []
        }

        var detections: [VisionDetection] = []

        for boxIndex in 0..<boxCount {
            var bestClass = 0
            var bestScore: Float = 0

            for classIndex in 0..<classCount {
                let score = confidence[[boxIndex, classIndex] as [NSNumber]].floatValue
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            guard bestScore >= confidenceThreshold else { continue }

            let label = Self.cocoClassNames.indices.contains(bestClass)
                ? Self.cocoClassNames[bestClass]
                : "object-\(bestClass)"

            guard isAerialLabel(label) else { continue }

            let cx = coordinates[[boxIndex, 0] as [NSNumber]].doubleValue
            let cy = coordinates[[boxIndex, 1] as [NSNumber]].doubleValue
            let width = coordinates[[boxIndex, 2] as [NSNumber]].doubleValue
            let height = coordinates[[boxIndex, 3] as [NSNumber]].doubleValue

            let rect = CGRect(
                x: cx - width / 2,
                y: 1 - (cy + height / 2),
                width: width,
                height: height
            ).standardized

            detections.append(
                VisionDetection(
                    label: displayLabel(for: label),
                    confidence: bestScore,
                    boundingBox: rect,
                    source: .vision
                )
            )
        }

        return detections
    }

    private func isAerialLabel(_ name: String) -> Bool {
        aerialLabels.contains(where: { name.contains($0) })
    }

    private func displayLabel(for name: String) -> String {
        if name.contains("airplane") || name.contains("aircraft") {
            return "Possible Drone"
        }
        if name.contains("bird") {
            return "Bird / UAV"
        }
        if name.contains("kite") {
            return "Aerial Object"
        }
        return name.capitalized
    }

    /// Must be called on `stateQueue`.
    private func runMotionHeuristic(current: CVPixelBuffer) -> [VisionDetection] {
        let width = CVPixelBufferGetWidth(current)
        let height = CVPixelBufferGetHeight(current)
        let grid = motionGrid

        CVPixelBufferLockBaseAddress(current, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(current, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(current) else { return [] }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(current)
        let cellWidth = max(width / grid, 1)
        let cellHeight = max(height / grid, 1)
        let step = 8
        var currentGrid = [Float](repeating: 0, count: grid * grid)

        for gy in 0..<grid {
            for gx in 0..<grid {
                var sum = 0
                var samples = 0
                let startY = gy * cellHeight
                let startX = gx * cellWidth

                for y in stride(from: startY, to: min(startY + cellHeight, height), by: step) {
                    for x in stride(from: startX, to: min(startX + cellWidth, width), by: step) {
                        let offset = y * bytesPerRow + x * 4
                        let pixel = base.load(fromByteOffset: offset, as: UInt32.self)
                        // Approximate luma from B channel-ish of BGRA packed value
                        sum += Int(pixel & 0xFF)
                        samples += 1
                    }
                }
                currentGrid[gy * grid + gx] = Float(sum) / Float(max(samples, 1))
            }
        }

        let previous = previousLumaGrid
        previousLumaGrid = currentGrid
        guard let previous, previous.count == currentGrid.count else { return [] }

        var hotCells: [(x: Int, y: Int, score: Float)] = []
        for gy in 0..<grid {
            for gx in 0..<grid {
                let idx = gy * grid + gx
                let score = abs(currentGrid[idx] - previous[idx])
                if score > 10 {
                    hotCells.append((gx, gy, score))
                }
            }
        }

        guard hotCells.count >= 1, hotCells.count <= 24 else { return [] }

        let avgX = hotCells.map(\.x).reduce(0, +) / hotCells.count
        let avgY = hotCells.map(\.y).reduce(0, +) / hotCells.count
        let avgScore = hotCells.map(\.score).reduce(0, +) / Float(hotCells.count)
        let normalizedConfidence = min(0.7, max(0.35, avgScore / 40))

        let boxWidth = CGFloat(2.5) / CGFloat(grid)
        let boxHeight = CGFloat(2.5) / CGFloat(grid)
        let originX = CGFloat(avgX) / CGFloat(grid) - boxWidth / 2
        let originY = 1 - (CGFloat(avgY) / CGFloat(grid)) - boxHeight / 2

        return [
            VisionDetection(
                label: "Moving Object",
                confidence: normalizedConfidence,
                boundingBox: CGRect(x: originX, y: originY, width: boxWidth, height: boxHeight),
                source: .motion
            )
        ]
    }

    private static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)

        var copy: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &copy
        )
        guard status == kCVReturnSuccess, let destination = copy else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }

        guard
            let src = CVPixelBufferGetBaseAddress(source),
            let dst = CVPixelBufferGetBaseAddress(destination)
        else { return nil }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(destination)

        if srcBytesPerRow == dstBytesPerRow {
            memcpy(dst, src, srcBytesPerRow * height)
        } else {
            let rowBytes = min(srcBytesPerRow, dstBytesPerRow)
            for row in 0..<height {
                memcpy(
                    dst.advanced(by: row * dstBytesPerRow),
                    src.advanced(by: row * srcBytesPerRow),
                    rowBytes
                )
            }
        }

        return destination
    }
}
