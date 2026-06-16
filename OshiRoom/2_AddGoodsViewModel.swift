import Foundation
import Observation
import SwiftUI
import UIKit

/// 写真選択、背景除去、画像保存までを担当するViewModelです。
@Observable
final class AddGoodsViewModel {
    var previewImage: UIImage?
    var pendingImagePath: String?
    var isProcessing = false
    var shouldRemoveBackground = true
    var message = "写真を選ぶと、背景削除の有無に合わせてグッズ画像を作成します。"

    private let backgroundRemovalService = BackgroundRemovalService()
    private var sourceImage: UIImage?

    func processCapturedImage(_ image: UIImage) async {
        isProcessing = true
        pendingImagePath = nil
        previewImage = nil
        defer { isProcessing = false }

        sourceImage = image
        await process(image)
    }

    func processPickedImage(_ image: UIImage) async {
        await processCapturedImage(image)
    }

    func reprocessCurrentImage() async {
        guard let sourceImage, !isProcessing else {
            return
        }

        isProcessing = true
        pendingImagePath = nil
        previewImage = nil
        defer { isProcessing = false }

        await process(sourceImage)
    }

    func commitPreparedGoods() -> (UIImage, String)? {
        guard let previewImage, let pendingImagePath else {
            return nil
        }

        return (previewImage, pendingImagePath)
    }

    func resetSelectedImage() {
        previewImage = nil
        pendingImagePath = nil
        sourceImage = nil
        isProcessing = false
        message = "もう一度写真を選ぶと、背景削除の有無に合わせてグッズ画像を作成します。"
    }

    private func process(_ image: UIImage) async {
        do {
            let normalizedImage = image.normalizedForRendering()
            let processedImage: UIImage

            if normalizedImage.containsTransparentPixels() {
                message = "透過部分を整えています。"
                processedImage = normalizedImage.croppedToVisibleAlphaBounds()
            } else if shouldRemoveBackground {
                message = "被写体を持ち上げています。"
                guard let removedImage = await backgroundRemovalService.removeBackground(from: normalizedImage) else {
                    message = "この写真では被写体の抽出がうまくできませんでした。別の角度や明るい背景で試してください。"
                    return
                }

                processedImage = removedImage
            } else {
                message = "背景をそのまま保存しています。"
                processedImage = normalizedImage
            }

            let imagePath = try ImageStore.save(processedImage)
            previewImage = processedImage
            pendingImagePath = imagePath
            message = "プレビューを確認してから「追加する」を押してください。"
        } catch {
            message = "画像の作成に失敗しました。もう一度試してください。"
        }
    }
}
