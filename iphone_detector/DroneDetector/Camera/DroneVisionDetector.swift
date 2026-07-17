import AVFoundation
import CoreML
import Foundation
import Vision

final class DroneVisionDetector: ObservableObject {
    @Published private(set) var detections: [VisionDetection] = []
    @Published private(set) var isModelLoaded = false
    @Published private(set) var modelName = "Model unavailable"
    @Published private(set) var loadError: String?
    /// Width / height of the video buffer used to produce `detections`.
    /// The overlay uses this to match `AVCaptureVideoPreviewLayer` aspect-fill cropping.
    @Published private(set) var frameAspectRatio: CGFloat = 9.0 / 16.0

    private struct VisionModelPipeline {
        let displayName: String
        let request: VNCoreMLRequest
        let classNames: [String]
        let acceptedTypes: Set<DetectableObjectType>
    }

    private struct PipelineLoadError: Error, CustomStringConvertible {
        let description: String
    }

    private var modelPipelines: [VisionModelPipeline] = []

    private let inferenceQueue = DispatchQueue(
        label: "com.vozhyk.drone-detector.inference",
        qos: .userInitiated
    )
    private let stateQueue = DispatchQueue(label: "com.vozhyk.drone-detector.vision-state")

    private var isYOLOBusy = false
    private var previousLumaGrid: [Float]?
    private var lastDetectionPublish = Date.distantPast
    private let confidenceThreshold: Float = 0.35
    private let maxDetectionAge: TimeInterval = 0.6
    private let motionGrid = 16
    private let requiredConfirmationFrames = 3
    private let confirmationWindow: TimeInterval = 0.5
    private let trackMatchIoU: CGFloat = 0.25

    private struct DetectionTrack {
        var objectType: DetectableObjectType
        var boundingBox: CGRect
        var hits: Int
        var lastSeen: Date
    }

    private var tracks: [DetectionTrack] = []

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

    private static let customClassNames = DetectableObjectType.allCases.map(\.rawValue)

    private var enabledTypes: Set<DetectableObjectType> = Set(DetectableObjectType.allCases)

    init() {
        loadModel()
    }

    @MainActor
    func updateEnabledTypes(_ types: Set<DetectableObjectType>) {
        stateQueue.sync {
            enabledTypes = types
        }
    }

    /// Called from the camera video queue. Keeps the green box near realtime.
    nonisolated func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Motion identifies image change only. It must never be promoted to a drone
        // detection: auto-exposure, hand movement, birds, and clouds all trigger it.
        // It is deliberately excluded from alerting until it can be combined with a
        // stable model track.
        DispatchQueue.main.async { [weak self] in self?.clearIfStale() }

        // --- Slow path: YOLO when free; drops frames instead of queueing lag ---
        let shouldRunYOLO = stateQueue.sync { () -> Bool in
            guard !modelPipelines.isEmpty, !isYOLOBusy else { return false }
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

            let pipelines = self.stateQueue.sync { self.modelPipelines }
            let yolo = pipelines.flatMap { pipeline in
                self.runVisionRequest(
                    pipeline.request,
                    on: frameCopy,
                    classNames: pipeline.classNames,
                    acceptedTypes: pipeline.acceptedTypes
                )
            }
            guard !yolo.isEmpty else { return }

            let confirmed = self.stateQueue.sync {
                self.confirmDetections(yolo.filter(Self.needsConfirmation))
            }
            let immediate = yolo.filter { !Self.needsConfirmation($0) }
            let publishable = Self.deduplicatedDetections(immediate + confirmed)
            guard !publishable.isEmpty else { return }

            DispatchQueue.main.async {
                self.frameAspectRatio = CGFloat(CVPixelBufferGetWidth(frameCopy)) /
                    CGFloat(max(CVPixelBufferGetHeight(frameCopy), 1))
                self.publish(publishable)
            }
        }
    }

    private func publish(_ results: [VisionDetection]) {
        guard !results.isEmpty else { return }
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
        var loadedPipelines: [VisionModelPipeline] = []
        var loadErrors: [String] = []

        switch makePipeline(
            resourceName: "DroneDetector",
            displayName: "Plane Drone Core ML",
            fallbackClassNames: Self.customClassNames,
            acceptedTypes: [.planeDrone]
        ) {
        case .success(let pipeline):
            loadedPipelines.append(pipeline)
        case .failure(let error):
            loadErrors.append(error.description)
        }

        switch makePipeline(
            resourceName: "YOLOv8n",
            displayName: "COCO YOLOv8n",
            fallbackClassNames: Self.cocoClassNames,
            acceptedTypes: Set(DetectableObjectType.allCases).subtracting([.planeDrone])
        ) {
        case .success(let pipeline):
            loadedPipelines.append(pipeline)
        case .failure(let error):
            loadErrors.append(error.description)
        }

        stateQueue.sync {
            self.modelPipelines = loadedPipelines
        }

        DispatchQueue.main.async {
            self.isModelLoaded = !loadedPipelines.isEmpty
            self.modelName = loadedPipelines.isEmpty
                ? "Drone models missing"
                : loadedPipelines.map(\.displayName).joined(separator: " + ")
            self.loadError = loadErrors.isEmpty ? nil : loadErrors.joined(separator: "\n")
        }
    }

    private func makePipeline(
        resourceName: String,
        displayName: String,
        fallbackClassNames: [String],
        acceptedTypes: Set<DetectableObjectType>
    ) -> Result<VisionModelPipeline, PipelineLoadError> {
        if let compiledURL = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") {
            return makePipeline(
                withModelAt: compiledURL,
                displayName: displayName,
                fallbackClassNames: fallbackClassNames,
                acceptedTypes: acceptedTypes
            )
        }

        guard let packageURL = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") else {
            return .failure(PipelineLoadError(description: "\(resourceName).mlpackage missing from app bundle"))
        }

        do {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            return makePipeline(
                withModelAt: compiledURL,
                displayName: displayName,
                fallbackClassNames: fallbackClassNames,
                acceptedTypes: acceptedTypes
            )
        } catch {
            return .failure(PipelineLoadError(description: "Failed to compile \(resourceName): \(error.localizedDescription)"))
        }
    }

    private func makePipeline(
        withModelAt url: URL,
        displayName: String,
        fallbackClassNames: [String],
        acceptedTypes: Set<DetectableObjectType>
    ) -> Result<VisionModelPipeline, PipelineLoadError> {
        do {
            let configuration = MLModelConfiguration()
            if #available(iOS 16.0, *) {
                configuration.computeUnits = .cpuAndNeuralEngine
            } else {
                configuration.computeUnits = .all
            }
            let model = try MLModel(contentsOf: url, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill

            return .success(VisionModelPipeline(
                displayName: displayName,
                request: request,
                classNames: Self.classNames(from: model) ?? fallbackClassNames,
                acceptedTypes: acceptedTypes
            ))
        } catch {
            return .failure(PipelineLoadError(description: "Failed to load \(displayName): \(error.localizedDescription)"))
        }
    }

    private func runVisionRequest(
        _ request: VNCoreMLRequest,
        on pixelBuffer: CVPixelBuffer,
        classNames: [String],
        acceptedTypes: Set<DetectableObjectType>
    ) -> [VisionDetection] {
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([request])
            guard let results = request.results, !results.isEmpty else { return [] }

            if let recognized = results as? [VNRecognizedObjectObservation] {
                return mapRecognizedObjects(recognized, acceptedTypes: acceptedTypes)
            }

            return mapFeatureValueObservations(
                results,
                classNames: classNames,
                acceptedTypes: acceptedTypes
            )
        } catch {
            return []
        }
    }

    private func mapRecognizedObjects(
        _ observations: [VNRecognizedObjectObservation],
        acceptedTypes: Set<DetectableObjectType>
    ) -> [VisionDetection] {
        let types = stateQueue.sync { enabledTypes }
        return observations.compactMap { observation in
            guard let top = observation.labels.first else { return nil }
            let name = top.identifier.lowercased()
            guard top.confidence >= confidenceThreshold,
                  let objectType = mapLabelToObjectType(name),
                  acceptedTypes.contains(objectType),
                  types.contains(objectType) else { return nil }

            return VisionDetection(
                label: objectType.title,
                confidence: top.confidence,
                boundingBox: observation.boundingBox,
                source: .vision,
                objectType: objectType
            )
        }
    }

    private func mapFeatureValueObservations(
        _ results: [Any],
        classNames: [String],
        acceptedTypes: Set<DetectableObjectType>
    ) -> [VisionDetection] {
        let activeTypes: Set<DetectableObjectType> = stateQueue.sync { self.enabledTypes }
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

            let activeClassNames = Self.classNames(classNames, matching: classCount)
            let rawLabel = activeClassNames.indices.contains(bestClass)
                ? activeClassNames[bestClass]
                : "object-\(bestClass)"

            guard let objectType = mapLabelToObjectType(rawLabel),
                  acceptedTypes.contains(objectType),
                  activeTypes.contains(objectType) else { continue }

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
                    label: objectType.title,
                    confidence: bestScore,
                    boundingBox: rect,
                    source: .vision,
                    objectType: objectType
                )
            )
        }

        return detections
    }

    private func mapLabelToObjectType(_ label: String) -> DetectableObjectType? {
        let value = label.lowercased()
        if value.contains("plane_drone") ||
            value.contains("plane drone") ||
            value.contains("fixed-wing drone") ||
            value.contains("fixed wing drone") {
            return .planeDrone
        }
        if value.contains("car") || value.contains("auto") {
            return .auto
        }
        if value.contains("airplane") || value.contains("aircraft") || value.contains("plane") {
            return .plane
        }
        if value.contains("drone") || value.contains("uav") || value.contains("quadcopter") {
            return .drone
        }
        if value.contains("bird") {
            return .bird
        }
        if value.contains("person") || value.contains("human") {
            return .human
        }
        if value.contains("bus") {
            return .bus
        }
        if value.contains("truck") {
            return .truck
        }
        if value.contains("motorcycle") {
            return .motorcycle
        }
        return nil
    }

    /// Requires consecutive, spatially consistent model observations before an item
    /// reaches the UI/HUD. Must be called on `stateQueue`.
    private func confirmDetections(_ candidates: [VisionDetection]) -> [VisionDetection] {
        let now = Date()
        tracks.removeAll { now.timeIntervalSince($0.lastSeen) > confirmationWindow }

        var confirmed: [VisionDetection] = []
        for candidate in candidates {
            if let index = tracks.firstIndex(where: {
                $0.objectType == candidate.objectType &&
                Self.iou($0.boundingBox, candidate.boundingBox) >= trackMatchIoU
            }) {
                tracks[index].boundingBox = candidate.boundingBox
                tracks[index].hits += 1
                tracks[index].lastSeen = now
                if tracks[index].hits >= requiredConfirmationFrames {
                    confirmed.append(candidate)
                }
            } else {
                tracks.append(DetectionTrack(
                    objectType: candidate.objectType,
                    boundingBox: candidate.boundingBox,
                    hits: 1,
                    lastSeen: now
                ))
            }
        }
        return confirmed
    }

    private static func iou(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private static func deduplicatedDetections(_ detections: [VisionDetection]) -> [VisionDetection] {
        let sorted = detections.sorted { lhs, rhs in
            let lhsPriority = detectionPriority(lhs)
            let rhsPriority = detectionPriority(rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }
            return lhs.confidence > rhs.confidence
        }

        var kept: [VisionDetection] = []
        for detection in sorted where !kept.contains(where: {
            shouldDeduplicate($0, detection) && iou($0.boundingBox, detection.boundingBox) > 0.45
        }) {
            kept.append(detection)
        }
        return kept
    }

    private static func shouldDeduplicate(_ lhs: VisionDetection, _ rhs: VisionDetection) -> Bool {
        if lhs.objectType == rhs.objectType {
            return true
        }

        let droneLike: Set<DetectableObjectType> = [.drone, .planeDrone, .plane, .bird]
        return droneLike.contains(lhs.objectType) && droneLike.contains(rhs.objectType)
    }

    private static func detectionPriority(_ detection: VisionDetection) -> Int {
        switch detection.objectType {
        case .planeDrone: return 100
        case .drone: return 90
        case .plane: return 80
        case .bird: return 70
        case .auto, .bus, .truck, .motorcycle, .human: return 60
        }
    }

    private static func needsConfirmation(_ detection: VisionDetection) -> Bool {
        switch detection.objectType {
        case .drone, .planeDrone:
            return true
        case .auto, .plane, .bird, .human, .bus, .truck, .motorcycle:
            return false
        }
    }

    private static func classNames(from model: MLModel) -> [String]? {
        guard
            let userDefined = model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: Any],
            let rawClasses = userDefined["classes"] as? String
        else { return nil }

        // Ultralytics Core ML export stores labels as e.g.
        // "{0: 'drone', 1: 'bird'}". Accept a JSON-style list too, so the
        // app remains compatible with equivalent exports.
        let pattern = #"(?:\d+\s*:\s*)?[\"']([^\"']+)[\"']"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(rawClasses.startIndex..., in: rawClasses)
        let names = expression.matches(in: rawClasses, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: rawClasses) else { return nil }
            return String(rawClasses[valueRange])
        }
        return names.isEmpty ? nil : names
    }

    private static func classNames(_ modelClassNames: [String], matching classCount: Int) -> [String] {
        if modelClassNames.count == classCount {
            return modelClassNames
        }
        if customClassNames.count == classCount {
            return customClassNames
        }
        return modelClassNames
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

        guard enabledTypes.contains(.drone) else { return [] }
        return [
            VisionDetection(
                label: DetectableObjectType.drone.title,
                confidence: normalizedConfidence,
                boundingBox: CGRect(x: originX, y: originY, width: boxWidth, height: boxHeight),
                source: .motion,
                objectType: .drone
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
