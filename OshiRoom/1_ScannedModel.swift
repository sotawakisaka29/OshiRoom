import Foundation
import SwiftData
import simd

/// 物体スキャンで作成した3Dモデルまたは試験用スキャン記録です。
@Model
final class ScannedModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var methodRawValue: String
    var statusRawValue: String
    var modelPath: String?
    var captureDirectoryPath: String?
    var thumbnailData: Data?
    var previewTransformData: Data?
    var lastOpenedAt: Date?
    var shotCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        method: ScanMethod,
        status: ScannedModelStatus = .captured,
        modelPath: String? = nil,
        captureDirectoryPath: String? = nil,
        thumbnailData: Data? = nil,
        previewTransform: TransformSnapshot = .identity,
        lastOpenedAt: Date? = nil,
        shotCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.methodRawValue = method.rawValue
        self.statusRawValue = status.rawValue
        self.modelPath = modelPath
        self.captureDirectoryPath = captureDirectoryPath
        self.thumbnailData = thumbnailData
        self.previewTransformData = try? JSONEncoder().encode(previewTransform)
        self.lastOpenedAt = lastOpenedAt
        self.shotCount = shotCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var method: ScanMethod {
        get { ScanMethod(rawValue: methodRawValue) ?? .lidar }
        set { methodRawValue = newValue.rawValue }
    }

    var status: ScannedModelStatus {
        get { ScannedModelStatus(rawValue: statusRawValue) ?? .captured }
        set { statusRawValue = newValue.rawValue }
    }

    var previewThumbnailData: Data? {
        if let thumbnailData {
            return thumbnailData
        }

        guard let captureDirectoryPath else {
            return nil
        }

        if let captureThumbnail = ScannedModelStore.loadCaptureThumbnailData(relativePath: captureDirectoryPath) {
            return captureThumbnail
        }

        guard let modelPath else {
            return nil
        }

        return ScannedModelStore.loadModelThumbnailData(relativePath: modelPath)
    }

    var previewTransformSnapshot: TransformSnapshot {
        get {
            guard let previewTransformData,
                  let snapshot = try? JSONDecoder().decode(TransformSnapshot.self, from: previewTransformData) else {
                return .identity
            }

            return snapshot
        }
        set {
            previewTransformData = try? JSONEncoder().encode(newValue)
        }
    }
}

enum ScanMethod: String, CaseIterable, Identifiable {
    case lidar
    case photogrammetry
    case objectCapture
    case trueDepth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lidar:
            "LiDARスキャン"
        case .photogrammetry:
            "フォトグラメトリ"
        case .objectCapture:
            "ObjectCapture"
        case .trueDepth:
            "TrueDepth補助"
        }
    }

    var shortTitle: String {
        switch self {
        case .lidar:
            "LiDAR"
        case .photogrammetry:
            "Photo"
        case .objectCapture:
            "Object"
        case .trueDepth:
            "Depth"
        }
    }

    var symbolName: String {
        switch self {
        case .lidar:
            "viewfinder"
        case .photogrammetry:
            "camera.aperture"
        case .objectCapture:
            "cube"
        case .trueDepth:
            "faceid"
        }
    }
}

enum ScannedModelStatus: String {
    case captured
    case processing
    case ready
    case failed

    var title: String {
        switch self {
        case .captured:
            "撮影済み"
        case .processing:
            "生成中"
        case .ready:
            "プレビュー可能"
        case .failed:
            "生成失敗"
        }
    }
}
