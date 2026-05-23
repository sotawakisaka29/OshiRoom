import Foundation
import SceneKit

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
