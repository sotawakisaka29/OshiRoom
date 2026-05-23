import AVFoundation
import SwiftUI
import UIKit

/// 前面TrueDepthカメラの深度マップを取得し、簡易点群へ変換します。
struct TrueDepthCaptureView: UIViewRepresentable {
    let onSnapshotUpdated: (TrueDepthSnapshot) -> Void
    let onStatusChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSnapshotUpdated: onSnapshotUpdated, onStatusChanged: onStatusChanged)
    }

    func makeUIView(context: Context) -> TrueDepthPreviewView {
        let previewView = TrueDepthPreviewView()
        context.coordinator.configure(previewView: previewView)
        return previewView
    }

    func updateUIView(_ uiView: TrueDepthPreviewView, context: Context) {}

    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }

    final class Coordinator: NSObject, AVCaptureDepthDataOutputDelegate {
        private let session = AVCaptureSession()
        private let depthOutput = AVCaptureDepthDataOutput()
        private let sessionQueue = DispatchQueue(label: "oshiroom.truedepth.session")
        private let depthQueue = DispatchQueue(label: "oshiroom.truedepth.depth")
        private let onSnapshotUpdated: (TrueDepthSnapshot) -> Void
        private let onStatusChanged: (String) -> Void
        private var lastUpdateDate = Date.distantPast

        init(
            onSnapshotUpdated: @escaping (TrueDepthSnapshot) -> Void,
            onStatusChanged: @escaping (String) -> Void
        ) {
            self.onSnapshotUpdated = onSnapshotUpdated
            self.onStatusChanged = onStatusChanged
        }

        func configure(previewView: TrueDepthPreviewView) {
            previewView.previewLayer.videoGravity = .resizeAspectFill
            previewView.previewLayer.session = session

            sessionQueue.async {
                self.configureSession()
            }
        }

        private func configureSession() {
            guard Self.authorizationStatusAllowsCamera else {
                DispatchQueue.main.async {
                    self.onStatusChanged("カメラ権限を許可してください。")
                }
                return
            }

            guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
                DispatchQueue.main.async {
                    self.onStatusChanged("この端末では前面TrueDepthカメラを利用できません。")
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.sessionPreset = .photo

                if session.canAddInput(input) {
                    session.addInput(input)
                }

                depthOutput.isFilteringEnabled = true
                depthOutput.setDelegate(self, callbackQueue: depthQueue)
                if session.canAddOutput(depthOutput) {
                    session.addOutput(depthOutput)
                }

                depthOutput.connection(with: .depthData)?.isEnabled = true
                session.commitConfiguration()
                session.startRunning()

                DispatchQueue.main.async {
                    self.onStatusChanged("前面カメラにフィギュアを近づけ、全体が入る距離で止めてください。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.onStatusChanged("TrueDepthカメラを開始できませんでした。")
                }
            }
        }

        func depthDataOutput(
            _ output: AVCaptureDepthDataOutput,
            didOutput depthData: AVDepthData,
            timestamp: CMTime,
            connection: AVCaptureConnection
        ) {
            guard Date().timeIntervalSince(lastUpdateDate) > 0.35 else {
                return
            }
            lastUpdateDate = Date()

            let snapshot = makeSnapshot(from: depthData)
            DispatchQueue.main.async {
                self.onSnapshotUpdated(snapshot)
                if let boundingBox = snapshot.boundingBox {
                    self.onStatusChanged("推定サイズ: \(boundingBox.sizeText)")
                } else {
                    self.onStatusChanged("物体の輪郭を検出中です。背景を無地にすると安定します。")
                }
            }
        }

        private func makeSnapshot(from depthData: AVDepthData) -> TrueDepthSnapshot {
            let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            let depthMap = convertedDepth.depthDataMap
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            }

            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                return TrueDepthSnapshot(points: [], boundingBox: nil, capturedAt: .now)
            }

            let calibrationData = convertedDepth.cameraCalibrationData
            let intrinsics = calibrationData?.intrinsicMatrix
            let referenceSize = calibrationData?.intrinsicMatrixReferenceDimensions ?? CGSize(width: width, height: height)
            let scaleX = Float(width) / Float(referenceSize.width)
            let scaleY = Float(height) / Float(referenceSize.height)
            let fx = (intrinsics?.columns.0.x ?? Float(width)) * scaleX
            let fy = (intrinsics?.columns.1.y ?? Float(height)) * scaleY
            let cx = (intrinsics?.columns.2.x ?? Float(width) * 0.5) * scaleX
            let cy = (intrinsics?.columns.2.y ?? Float(height) * 0.5) * scaleY

            let sampleStride = max(2, min(width, height) / 64)
            var candidates: [SIMD3<Float>] = []
            candidates.reserveCapacity((width / sampleStride) * (height / sampleStride))

            for y in stride(from: height / 5, to: height * 4 / 5, by: sampleStride) {
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in stride(from: width / 5, to: width * 4 / 5, by: sampleStride) {
                    let depth = row[x]
                    guard depth.isFinite, depth > 0.08, depth < 0.75 else {
                        continue
                    }

                    let worldX = (Float(x) - cx) * depth / fx
                    let worldY = -(Float(y) - cy) * depth / fy
                    candidates.append([worldX, worldY, depth])
                }
            }

            guard candidates.isEmpty == false else {
                return TrueDepthSnapshot(points: [], boundingBox: nil, capturedAt: .now)
            }

            let sortedDepths = candidates.map(\.z).sorted()
            let medianDepth = sortedDepths[sortedDepths.count / 2]
            let objectPoints = candidates.filter { abs($0.z - medianDepth) < 0.10 }
            let previewPoints = downsample(objectPoints, limit: 650)
            let boundingBox = makeBoundingBox(from: objectPoints)

            return TrueDepthSnapshot(
                points: previewPoints.map(ScannedMeshVertex.init),
                boundingBox: boundingBox,
                capturedAt: .now
            )
        }

        private func downsample(_ points: [SIMD3<Float>], limit: Int) -> [SIMD3<Float>] {
            guard points.count > limit else {
                return points
            }

            let step = max(1, points.count / limit)
            return stride(from: 0, to: points.count, by: step).map { points[$0] }
        }

        private func makeBoundingBox(from points: [SIMD3<Float>]) -> TrueDepthBoundingBox? {
            guard let firstPoint = points.first else {
                return nil
            }

            let bounds = points.reduce((min: firstPoint, max: firstPoint)) { partialResult, point in
                (
                    min: simd_min(partialResult.min, point),
                    max: simd_max(partialResult.max, point)
                )
            }

            return TrueDepthBoundingBox(
                min: ScannedMeshVertex(bounds.min),
                max: ScannedMeshVertex(bounds.max)
            )
        }

        private static var authorizationStatusAllowsCamera: Bool {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                return true
            case .notDetermined:
                let semaphore = DispatchSemaphore(value: 0)
                var isGranted = false
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    isGranted = granted
                    semaphore.signal()
                }
                semaphore.wait()
                return isGranted
            default:
                return false
            }
        }
    }
}

final class TrueDepthPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
