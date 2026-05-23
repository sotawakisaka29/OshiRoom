import AVFoundation
import SwiftUI
import UIKit

/// Object Capture UIに依存せず、通常の背面カメラでフォトグラメトリ用写真を集めます。
struct ManualPhotogrammetryCaptureView: UIViewRepresentable {
    let captureDirectoryURL: URL
    let captureRequestToken: Int
    let onPhotoCaptured: (Int) -> Void
    let onStatusChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            captureDirectoryURL: captureDirectoryURL,
            onPhotoCaptured: onPhotoCaptured,
            onStatusChanged: onStatusChanged
        )
    }

    func makeUIView(context: Context) -> ManualCameraPreviewView {
        let previewView = ManualCameraPreviewView()
        context.coordinator.configure(previewView: previewView)
        return previewView
    }

    func updateUIView(_ uiView: ManualCameraPreviewView, context: Context) {
        context.coordinator.captureDirectoryURL = captureDirectoryURL
        context.coordinator.captureIfNeeded(token: captureRequestToken)
    }

    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    final class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        var captureDirectoryURL: URL
        private let session = AVCaptureSession()
        private let photoOutput = AVCapturePhotoOutput()
        private let sessionQueue = DispatchQueue(label: "oshiroom.manual-photogrammetry.session")
        private let onPhotoCaptured: (Int) -> Void
        private let onStatusChanged: (String) -> Void
        private var handledCaptureRequestToken = 0
        private var capturedCount = 0

        init(
            captureDirectoryURL: URL,
            onPhotoCaptured: @escaping (Int) -> Void,
            onStatusChanged: @escaping (String) -> Void
        ) {
            self.captureDirectoryURL = captureDirectoryURL
            self.onPhotoCaptured = onPhotoCaptured
            self.onStatusChanged = onStatusChanged
        }

        func configure(previewView: ManualCameraPreviewView) {
            previewView.previewLayer.videoGravity = .resizeAspectFill
            previewView.previewLayer.session = session

            sessionQueue.async {
                self.configureSession()
            }
        }

        func captureIfNeeded(token: Int) {
            guard token != handledCaptureRequestToken else {
                return
            }

            handledCaptureRequestToken = token
            sessionQueue.async {
                guard self.session.isRunning else {
                    DispatchQueue.main.async {
                        self.onStatusChanged("カメラ準備中です。少し待ってから撮影してください。")
                    }
                    return
                }

                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }

        private func configureSession() {
            guard Self.authorizationStatusAllowsCamera else {
                DispatchQueue.main.async {
                    self.onStatusChanged("カメラ権限を許可してください。")
                }
                return
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async {
                    self.onStatusChanged("背面カメラを利用できません。")
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

                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                }

                session.commitConfiguration()
                session.startRunning()

                DispatchQueue.main.async {
                    self.onStatusChanged("物体を中心に入れ、少しずつ角度を変えて撮影してください。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.onStatusChanged("カメラを開始できませんでした。")
                }
            }
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            if let error {
                DispatchQueue.main.async {
                    self.onStatusChanged("撮影に失敗しました: \(error.localizedDescription)")
                }
                return
            }

            guard let data = photo.fileDataRepresentation() else {
                DispatchQueue.main.async {
                    self.onStatusChanged("写真データを保存できませんでした。")
                }
                return
            }

            capturedCount += 1
            let fileURL = captureDirectoryURL.appendingPathComponent(
                String(format: "photo_%03d.jpg", capturedCount)
            )

            do {
                try data.write(to: fileURL, options: [.atomic])
                DispatchQueue.main.async {
                    self.onPhotoCaptured(self.capturedCount)
                    self.onStatusChanged("撮影枚数: \(self.capturedCount)。80枚前後あると安定しやすいです。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.onStatusChanged("写真の保存に失敗しました。")
                }
            }
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

final class ManualCameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
