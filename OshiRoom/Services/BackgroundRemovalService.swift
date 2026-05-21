import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Visionを使い、写真から前景だけを取り出した透明PNG風の画像を作ります。
struct BackgroundRemovalService {
    private let context = CIContext()

    func removeBackground(from image: UIImage) async -> UIImage {
        let normalizedImage = image.normalizedForRendering()

        guard let cgImage = normalizedImage.cgImage else {
            return normalizedImage
        }

        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            guard let result = request.results?.first else {
                return normalizedImage
            }

            let maskBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            return applyAlphaMask(maskBuffer, to: cgImage, scale: normalizedImage.scale) ?? normalizedImage
        } catch {
            return normalizedImage
        }
    }

    private func applyAlphaMask(
        _ maskBuffer: CVPixelBuffer,
        to cgImage: CGImage,
        scale: CGFloat
    ) -> UIImage? {
        let inputImage = CIImage(cgImage: cgImage)
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let clearBackground = CIImage(color: .clear).cropped(to: inputImage.extent)
        let filter = CIFilter.blendWithAlphaMask()

        filter.inputImage = inputImage
        filter.backgroundImage = clearBackground
        filter.maskImage = maskImage

        guard let outputImage = filter.outputImage,
              let outputCGImage = context.createCGImage(outputImage, from: inputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: outputCGImage, scale: scale, orientation: .up)
    }
}
