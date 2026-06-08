import AVFoundation
import Foundation

@main
struct TrimPromotionVideo {
    static func main() throws {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: "/private/tmp/My_Oshi_Room_Promo_15s.mp4")
        let outputURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("My_Oshi_Room_Promo_15s.mp4")

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "TrimPromotionVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "書き出しセッションを作成できませんでした。"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 15, preferredTimescale: 600)
        )

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? NSError(domain: "TrimPromotionVideo", code: 2, userInfo: [NSLocalizedDescriptionKey: "動画の切り出しに失敗しました。"])
        }

        print(outputURL.path)
    }
}
