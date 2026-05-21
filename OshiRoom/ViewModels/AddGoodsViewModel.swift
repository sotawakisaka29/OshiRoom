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
    var isProcessing = false
    var message = "写真を選ぶと、背景を除去して薄いアクスタ風オブジェクトにします。"

    private let backgroundRemovalService = BackgroundRemovalService()

    func loadSelectedImage() async -> (UIImage, String)? {
        guard let selectedItem else {
            return nil
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                message = "画像を読み込めませんでした。別の写真で試してください。"
                return nil
            }

            return await process(image)
        } catch {
            message = "画像の作成に失敗しました。もう一度試してください。"
            return nil
        }
    }

    func processCapturedImage(_ image: UIImage) async -> (UIImage, String)? {
        isProcessing = true
        defer { isProcessing = false }

        return await process(image)
    }

    private func process(_ image: UIImage) async -> (UIImage, String)? {
        do {
            message = "背景を除去しています。"
            let processedImage = await backgroundRemovalService.removeBackground(from: image)
            let imagePath = try ImageStore.save(processedImage)
            previewImage = processedImage
            message = "背景除去が完了しました。"
            return (processedImage, imagePath)
        } catch {
            message = "画像の作成に失敗しました。もう一度試してください。"
            return nil
        }
    }
}
