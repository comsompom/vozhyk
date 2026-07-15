import CoreML
import CoreImage
import Foundation
import Vision

@MainActor
final class DroneVisionDetector: ObservableObject {
    @Published private(set) var detections: [VisionDetection] = []
    @Published private(set) var isModelLoaded = false
    @Published private(set) var modelName = "Motion + Aerial Heuristics"

    private var visionModel: VNCoreMLModel?
    private var sequenceHandler = VNSequenceRequestHandler()
    private var previousFrame: CVPixelBuffer?
    private let confidenceThreshold: Float = 0.35
    private let aerialLabels: Set<String> = [
        "airplane", "aircraft", "bird", "kite", "drone", "uav", "quadcopter", "flying"
    ]

    init() {
        loadModel()
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var results: [VisionDetection] = []

        if let visionModel {
            results.append(contentsOf: runCoreMLDetection(on: pixelBuffer, model: visionModel))
        }

        if results.isEmpty {
            results.append(contentsOf: runMotionHeuristic(current: pixelBuffer))
        }

        detections = results
    }

    private func loadModel() {
        if let compiledURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlmodelc") {
            loadModel(from: compiledURL, name: "YOLOv8n")
            return
        }

        if let packageURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlpackage") {
            do {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                loadModel(from: compiledURL, name: "YOLOv8n")
            } catch {
                modelName = "Motion + Aerial Heuristics (add YOLOv8n model for AI)"
            }
            return
        }

        modelName = "Motion + Aerial Heuristics (add YOLOv8n model for AI)"
    }

    private func loadModel(from url: URL, name: String) {
        do {
            let model = try MLModel(contentsOf: url)
            visionModel = try VNCoreMLModel(for: model)
            isModelLoaded = true
            modelName = name
        } catch {
            modelName = "Motion + Aerial Heuristics"
        }
    }

    private func runCoreMLDetection(on pixelBuffer: CVPixelBuffer, model: VNCoreMLModel) -> [VisionDetection] {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                return []
            }

            return observations.compactMap { observation in
                guard let label = observation.labels.first else { return nil }
                let name = label.identifier.lowercased()
                guard aerialLabels.contains(where: { name.contains($0) }) || label.confidence >= 0.55 else {
                    return nil
                }
                guard label.confidence >= confidenceThreshold else { return nil }

                return VisionDetection(
                    label: label.identifier.capitalized,
                    confidence: label.confidence,
                    boundingBox: observation.boundingBox,
                    source: .vision
                )
            }
        } catch {
            return []
        }
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
        let cellWidth = width / grid
        let cellHeight = height / grid
        var hotCells: [(x: Int, y: Int, score: Float)] = []

        for gy in 0..<grid {
            for gx in 0..<grid {
                var diff: Int = 0
                var samples = 0
                let startY = gy * cellHeight
                let startX = gx * cellWidth

                for y in stride(from: startY, to: min(startY + cellHeight, height), by: 4) {
                    for x in stride(from: startX, to: min(startX + cellWidth, width), by: 4) {
                        let offset = y * bytesPerRow + x * 4
                        let currentPixel = currentBase.load(fromByteOffset: offset, as: UInt32.self)
                        let previousPixel = previousBase.load(fromByteOffset: offset, as: UInt32.self)
                        diff += abs(Int(currentPixel) - Int(previousPixel))
                        samples += 1
                    }
                }

                let score = Float(diff) / Float(max(samples, 1))
                if score > 18_000 {
                    hotCells.append((gx, gy, score))
                }
            }
        }

        guard !hotCells.isEmpty else { return [] }

        let avgX = hotCells.map(\.x).reduce(0, +) / hotCells.count
        let avgY = hotCells.map(\.y).reduce(0, +) / hotCells.count
        let avgScore = hotCells.map(\.score).reduce(0, +) / Float(hotCells.count)
        let normalizedConfidence = min(0.85, max(0.4, avgScore / 40_000))

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
