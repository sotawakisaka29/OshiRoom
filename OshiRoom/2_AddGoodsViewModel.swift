import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

/// 写真選択、背景除去、画像保存までを担当するViewModelです。
@Observable
final class AddGoodsViewModel {
    var selectedItem: PhotosPickerItem?
    var previewImage: UIImage?
    var pendingImagePath: String?
    var isProcessing = false
    var message = "写真を選ぶと、背景を除去して薄いアクスタ風オブジェクトにします。"

    private let backgroundRemovalService = BackgroundRemovalService()

    func loadSelectedImage() async {
        guard let selectedItem else {
            return
        }

        isProcessing = true
        pendingImagePath = nil
        previewImage = nil
        defer { isProcessing = false }

        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                message = "画像を読み込めませんでした。別の写真で試してください。"
                return
            }

            await process(image)
        } catch {
            message = "画像の作成に失敗しました。もう一度試してください。"
        }
    }

    func processCapturedImage(_ image: UIImage) async {
        isProcessing = true
        pendingImagePath = nil
        previewImage = nil
        defer { isProcessing = false }

        await process(image)
    }

    func commitPreparedGoods() -> (UIImage, String)? {
        guard let previewImage, let pendingImagePath else {
            return nil
        }

        return (previewImage, pendingImagePath)
    }

    private func process(_ image: UIImage) async {
        do {
            let normalizedImage = image.normalizedForRendering()
            let processedImage: UIImage

            if normalizedImage.containsTransparentPixels() {
                message = "透過PNGを整えています。"
                processedImage = normalizedImage.croppedToVisibleAlphaBounds()
            } else {
                message = "背景を除去しています。"
                processedImage = await backgroundRemovalService
                    .removeBackground(from: normalizedImage)
                    .croppedToVisibleAlphaBounds()
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
