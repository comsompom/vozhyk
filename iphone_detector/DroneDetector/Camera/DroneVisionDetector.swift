import AVFoundation
import CoreML
import Foundation
import Vision

@MainActor
final class DroneVisionDetector: ObservableObject {
    @Published private(set) var detections: [VisionDetection] = []
    @Published private(set) var isModelLoaded = false
    @Published private(set) var modelName = "Motion + Aerial Heuristics"
    @Published private(set) var loadError: String?

    private var visionModel: VNCoreMLModel?
    private var request: VNCoreMLRequest?
    private var sequenceHandler = VNSequenceRequestHandler()
    private var previousFrame: CVPixelBuffer?
    private var frameCounter = 0
    private let processEveryNFrames = 2
    private let confidenceThreshold: Float = 0.25

    /// COCO-80 labels used by YOLOv8n (indexes match model confidence channels).
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

    /// Aerial / drone-proxy COCO classes (and common synonyms).
    private let aerialLabels: Set<String> = [
        "airplane", "aircraft", "bird", "kite", "drone", "uav", "quadcopter", "flying"
    ]

    init() {
        loadModel()
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameCounter += 1
        if frameCounter % processEveryNFrames != 0 { return }

        var results: [VisionDetection] = []

        if let request {
            results.append(contentsOf: runVisionRequest(request, on: pixelBuffer))
        }

        if results.isEmpty {
            results.append(contentsOf: runMotionHeuristic(current: pixelBuffer))
        }

        detections = results
    }

    private func loadModel() {
        // Prefer Xcode-generated wrapper (compiled into the app from YOLOv8n.mlpackage).
        if let bundled = try? YOLOv8n(configuration: {
            let config = MLModelConfiguration()
            config.computeUnits = .all
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
                loadError = "Failed to compile YOLOv8n: \(error.localizedDescription)"
                modelName = "Motion fallback (model compile failed)"
            }
            return
        }

        loadError = "YOLOv8n.mlpackage missing from app bundle"
        modelName = "Motion + Aerial Heuristics (model not in bundle)"
    }

    private func configure(with model: MLModel, displayName: String) {
        do {
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill

            self.visionModel = visionModel
            self.request = request
            isModelLoaded = true
            loadError = nil
            modelName = displayName
        } catch {
            loadError = error.localizedDescription
            modelName = "Motion fallback (model load failed)"
            isModelLoaded = false
            visionModel = nil
            request = nil
        }
    }

    private func configure(withModelAt url: URL, displayName: String) {
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: configuration)
            configure(with: model, displayName: displayName)
        } catch {
            loadError = error.localizedDescription
            modelName = "Motion fallback (model load failed)"
            isModelLoaded = false
            visionModel = nil
            request = nil
        }
    }

    private func runVisionRequest(_ request: VNCoreMLRequest, on pixelBuffer: CVPixelBuffer) -> [VisionDetection] {
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
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

    /// Fallback for YOLO Core ML exports that return raw confidence/coordinates tensors.
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

            // YOLO Core ML coords are normalized center-x/y/width/height.
            // Vision overlay space expects bottom-left origin.
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

    private func runMotionHeuristic(current: CVPixelBuffer) -> [VisionDetection] {
        defer { previousFrame = current }

        guard let previousFrame else { return [] }

        let width = CVPixelBufferGetWidth(current)
        let height = CVPixelBufferGetHeight(current)
        guard width == CVPixelBufferGetWidth(previousFrame),
              height == CVPixelBufferGetHeight(previousFrame) else { return [] }

        CVPixelBufferLockBaseAddress(current, .readOnly)
        CVPixelBufferLockBaseAddress(previousFrame, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(current, .readOnly)
            CVPixelBufferUnlockBaseAddress(previousFrame, .readOnly)
        }

        guard
            let currentBase = CVPixelBufferGetBaseAddress(current),
            let previousBase = CVPixelBufferGetBaseAddress(previousFrame)
        else { return [] }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(current)
        let grid = 24
        let cellWidth = max(width / grid, 1)
        let cellHeight = max(height / grid, 1)
        var hotCells: [(x: Int, y: Int, score: Float)] = []

        for gy in 0..<grid {
            for gx in 0..<grid {
                var diff = 0
                var samples = 0
                let startY = gy * cellHeight
                let startX = gx * cellWidth

                for y in stride(from: startY, to: min(startY + cellHeight, height), by: 4) {
                    for x in stride(from: startX, to: min(startX + cellWidth, width), by: 4) {
                        let offset = y * bytesPerRow + x * 4
                        let currentPixel = currentBase.load(fromByteOffset: offset, as: UInt32.self)
                        let previousPixel = previousBase.load(fromByteOffset: offset, as: UInt32.self)
                        diff += abs(Int(currentPixel & 0xFF) - Int(previousPixel & 0xFF))
                        samples += 1
                    }
                }

                let score = Float(diff) / Float(max(samples, 1))
                if score > 12 {
                    hotCells.append((gx, gy, score))
                }
            }
        }

        // Require a compact moving blob; ignore whole-frame camera shake.
        guard hotCells.count >= 1, hotCells.count <= 40 else { return [] }

        let avgX = hotCells.map(\.x).reduce(0, +) / hotCells.count
        let avgY = hotCells.map(\.y).reduce(0, +) / hotCells.count
        let avgScore = hotCells.map(\.score).reduce(0, +) / Float(hotCells.count)
        let normalizedConfidence = min(0.75, max(0.35, avgScore / 40))

        let boxWidth = CGFloat(2) / CGFloat(grid)
        let boxHeight = CGFloat(2) / CGFloat(grid)
        let originX = CGFloat(avgX) / CGFloat(grid) - boxWidth / 2
        let originY = 1 - (CGFloat(avgY) / CGFloat(grid)) - boxHeight / 2

        return [
            VisionDetection(
                label: "Moving Aerial Object",
                confidence: normalizedConfidence,
                boundingBox: CGRect(x: originX, y: originY, width: boxWidth, height: boxHeight),
                source: .motion
            )
        ]
    }
}
