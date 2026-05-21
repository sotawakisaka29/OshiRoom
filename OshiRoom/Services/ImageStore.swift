import Foundation
import UIKit

/// 生成したグッズ画像をアプリ内のDocumentsフォルダへ保存します。
enum ImageStore {
    static let goodsFolderName = "GoodsImages"

    static func save(_ image: UIImage, id: UUID = UUID()) throws -> String {
        let folderURL = try goodsFolderURL()
        let fileURL = folderURL.appendingPathComponent("\(id.uuidString).png")
        let normalizedImage = image.normalizedForRendering()

        guard let data = normalizedImage.pngData() else {
            throw ImageStoreError.cannotCreatePNG
        }

        try data.write(to: fileURL, options: [.atomic])
        return fileURL.lastPathComponent
    }

    static func load(path: String) -> UIImage? {
        guard let folderURL = try? goodsFolderURL() else {
            return nil
        }

        let fileURL = folderURL.appendingPathComponent(path)
        return UIImage(contentsOfFile: fileURL.path)
    }

    static func url(for path: String) -> URL? {
        guard let folderURL = try? goodsFolderURL() else {
            return nil
        }

        return folderURL.appendingPathComponent(path)
    }

    static func delete(path: String) {
        guard let folderURL = try? goodsFolderURL() else {
            return
        }

        let fileURL = folderURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func goodsFolderURL() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folderURL = documentsURL.appendingPathComponent(goodsFolderName, isDirectory: true)

        if FileManager.default.fileExists(atPath: folderURL.path) == false {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        return folderURL
    }
}

enum ImageStoreError: Error {
    case cannotCreatePNG
}
