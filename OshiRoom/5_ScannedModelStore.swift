import Foundation
import Metal
import SceneKit
import UIKit

struct ScannedModelSaveResult {
    let captureDirectoryPath: String
    let modelPath: String
}

/// スキャン画像と生成済みUSDZをDocuments配下で管理します。
enum ScannedModelStore {
    private static let rootFolderName = "ScannedModels"

    static func createCaptureDirectory(for id: UUID) throws -> String {
        let directoryName = "\(id.uuidString)-images"
        let directoryURL = try rootURL().appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryName
    }

    static func createLiDARSnapshotDirectory(for id: UUID, snapshot: ScannedMeshSnapshot) throws -> ScannedModelSaveResult {
        let directoryName = "\(id.uuidString)-lidar"
        let directoryURL = try rootURL().appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let metadataURL = directoryURL.appendingPathComponent("scan.json")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: metadataURL, options: [.atomic])

        let modelPath = modelFileName(for: id)
        if let modelURL = url(forRelativePath: modelPath) {
            try exportLiDARSnapshot(snapshot, to: modelURL)
        }

        return ScannedModelSaveResult(captureDirectoryPath: directoryName, modelPath: modelPath)
    }

    static func loadLiDARSnapshot(relativePath: String) -> ScannedMeshSnapshot? {
        guard let directoryURL = url(forRelativePath: relativePath) else {
            return nil
        }

        let metadataURL = directoryURL.appendingPathComponent("scan.json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }

        return try? JSONDecoder().decode(ScannedMeshSnapshot.self, from: data)
    }

    static func createTrueDepthSnapshotDirectory(for id: UUID, snapshot: TrueDepthSnapshot) throws -> ScannedModelSaveResult {
        let directoryName = "\(id.uuidString)-truedepth"
        let directoryURL = try rootURL().appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let metadataURL = directoryURL.appendingPathComponent("truedepth.json")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: metadataURL, options: [.atomic])

        let modelPath = modelFileName(for: id)
        if let modelURL = url(forRelativePath: modelPath) {
            try exportTrueDepthSnapshot(snapshot, to: modelURL)
        }

        return ScannedModelSaveResult(captureDirectoryPath: directoryName, modelPath: modelPath)
    }

    static func loadTrueDepthSnapshot(relativePath: String) -> TrueDepthSnapshot? {
        guard let directoryURL = url(forRelativePath: relativePath) else {
            return nil
        }

        let metadataURL = directoryURL.appendingPathComponent("truedepth.json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }

        return try? JSONDecoder().decode(TrueDepthSnapshot.self, from: data)
    }

    static func loadCaptureThumbnailData(relativePath: String) -> Data? {
        guard let directoryURL = url(forRelativePath: relativePath) else {
            return nil
        }

        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let imageURL = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.first { url in
            let lowercased = url.pathExtension.lowercased()
            return lowercased == "jpg" || lowercased == "jpeg" || lowercased == "png"
        }

        guard let imageURL,
              let image = UIImage(contentsOfFile: imageURL.path) else {
            return nil
        }

        return image.encodedThumbnailData()
    }

    static func loadModelThumbnailData(relativePath: String) -> Data? {
        guard let modelURL = url(forRelativePath: relativePath),
              let scene = try? SCNScene(url: modelURL, options: nil),
              let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        let renderedSize = CGSize(width: 512, height: 512)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        scene.background.contents = UIColor.systemBackground

        let cameraNode = makeThumbnailCameraNode(for: scene)
        scene.rootNode.addChildNode(cameraNode)
        renderer.pointOfView = cameraNode

        let image = renderer.snapshot(
            atTime: 0,
            with: renderedSize,
            antialiasingMode: .multisampling4X
        )
        return image.encodedThumbnailData(maxPixelLength: 320, compressionQuality: 0.7)
    }

    static func modelFileName(for id: UUID) -> String {
        "\(id.uuidString).usdz"
    }

    static func url(forRelativePath relativePath: String) -> URL? {
        guard let rootURL = try? rootURL() else {
            return nil
        }

        return rootURL.appendingPathComponent(relativePath)
    }

    static func delete(relativePath: String) throws {
        guard let url = url(forRelativePath: relativePath),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    private static func rootURL() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = documentsURL.appendingPathComponent(rootFolderName, isDirectory: true)

        if FileManager.default.fileExists(atPath: rootURL.path) == false {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    private static func exportLiDARSnapshot(_ snapshot: ScannedMeshSnapshot, to url: URL) throws {
        let scene = SCNScene()
        guard snapshot.isEmpty == false else {
            try scene.writeUSDZ(to: url)
            return
        }

        let allVertices = snapshot.anchors.flatMap { $0.vertices.map(\.simdValue) }
        guard allVertices.isEmpty == false else {
            try scene.writeUSDZ(to: url)
            return
        }

        let center = allVertices.reduce(SIMD3<Float>.zero, +) / Float(allVertices.count)
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for anchor in snapshot.anchors {
            let baseIndex = Int32(vertices.count)
            vertices.append(contentsOf: anchor.vertices.map { vertex in
                let centered = vertex.simdValue - center
                return SCNVector3(centered.x, centered.y, centered.z)
            })
            indices.append(contentsOf: anchor.triangleIndices.map { Int32($0) + baseIndex })
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [makeMaterial(color: UIColor(red: 0.20, green: 0.48, blue: 0.92, alpha: 0.85))]

        let node = SCNNode(geometry: geometry)
        node.scale = SCNVector3(0.55, 0.55, 0.55)
        scene.rootNode.addChildNode(node)
        try scene.writeUSDZ(to: url)
    }

    private static func exportTrueDepthSnapshot(_ snapshot: TrueDepthSnapshot, to url: URL) throws {
        let scene = SCNScene()
        guard snapshot.isEmpty == false else {
            try scene.writeUSDZ(to: url)
            return
        }

        let vectors = snapshot.points.map(\.simdValue)
        let center = vectors.reduce(SIMD3<Float>.zero, +) / Float(vectors.count)
        let pointMaterial = makeMaterial(color: UIColor(red: 0.10, green: 0.56, blue: 0.42, alpha: 0.9))

        for vector in vectors {
            let sphere = SCNSphere(radius: 0.004)
            sphere.segmentCount = 6
            sphere.materials = [pointMaterial]
            let node = SCNNode(geometry: sphere)
            let centered = vector - center
            node.position = SCNVector3(centered.x, centered.y, centered.z)
            scene.rootNode.addChildNode(node)
        }

        if let boundingBox = snapshot.boundingBox {
            let size = SIMD3<Float>(
                max(boundingBox.width, 0.01),
                max(boundingBox.height, 0.01),
                max(boundingBox.depth, 0.01)
            )
            let boxGeometry = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0
            )
            boxGeometry.materials = [makeMaterial(color: UIColor(red: 0.10, green: 0.56, blue: 0.42, alpha: 0.22))]
            let boxNode = SCNNode(geometry: boxGeometry)
            let position = (boundingBox.min.simdValue + boundingBox.max.simdValue) * 0.5 - center
            boxNode.position = SCNVector3(position.x, position.y, position.z)
            scene.rootNode.addChildNode(boxNode)
        }

        scene.rootNode.scale = SCNVector3(1.2, 1.2, 1.2)
        try scene.writeUSDZ(to: url)
    }

    private static func makeMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.transparency = CGFloat(color.cgColor.alpha)
        material.isDoubleSided = true
        material.lightingModel = .physicallyBased
        return material
    }

    private static func makeThumbnailCameraNode(for scene: SCNScene) -> SCNNode {
        let bounds = aggregateBoundingBox(for: scene.rootNode) ?? (
            min: SCNVector3(-0.2, -0.2, -0.2),
            max: SCNVector3(0.2, 0.2, 0.2)
        )

        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        let extentX = bounds.max.x - bounds.min.x
        let extentY = bounds.max.y - bounds.min.y
        let extentZ = bounds.max.z - bounds.min.z
        let maxExtent = max(extentX, extentY, extentZ, 0.01)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 55
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(
            center.x,
            center.y + maxExtent * 0.15,
            center.z + maxExtent * 2.3
        )
        cameraNode.look(at: center)

        let light = SCNLight()
        light.type = .omni
        light.intensity = 1600
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(
            center.x + maxExtent * 0.8,
            center.y + maxExtent * 1.2,
            center.z + maxExtent * 1.4
        )
        cameraNode.addChildNode(lightNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 550
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        return cameraNode
    }

    private static func aggregateBoundingBox(for node: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var found = false

        func visit(_ current: SCNNode) {
            if current.geometry != nil {
                let (localMin, localMax) = current.boundingBox
                let corners = [
                    SCNVector3(localMin.x, localMin.y, localMin.z),
                    SCNVector3(localMin.x, localMin.y, localMax.z),
                    SCNVector3(localMin.x, localMax.y, localMin.z),
                    SCNVector3(localMin.x, localMax.y, localMax.z),
                    SCNVector3(localMax.x, localMin.y, localMin.z),
                    SCNVector3(localMax.x, localMin.y, localMax.z),
                    SCNVector3(localMax.x, localMax.y, localMin.z),
                    SCNVector3(localMax.x, localMax.y, localMax.z)
                ]

                for corner in corners {
                    let world = current.convertPosition(corner, to: nil)
                    minX = min(minX, world.x)
                    minY = min(minY, world.y)
                    minZ = min(minZ, world.z)
                    maxX = max(maxX, world.x)
                    maxY = max(maxY, world.y)
                    maxZ = max(maxZ, world.z)
                    found = true
                }
            }

            for child in current.childNodes {
                visit(child)
            }
        }

        visit(node)

        guard found else {
            return nil
        }

        return (
            min: SCNVector3(minX, minY, minZ),
            max: SCNVector3(maxX, maxY, maxZ)
        )
    }
}

private extension SCNScene {
    func writeUSDZ(to url: URL) throws {
        var writeError: Error?
        let succeeded = write(to: url, options: nil, delegate: nil) { _, error, stop in
            if let error {
                writeError = error
                stop.pointee = true
            }
        }

        if let writeError {
            throw writeError
        }

        if succeeded == false {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
