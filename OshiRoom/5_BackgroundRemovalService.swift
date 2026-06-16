import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import VisionKit

/// VisionKitのsubject liftingを優先し、必要ならVisionの前景抽出にフォールバックします。
struct BackgroundRemovalService {
    private let context = CIContext()
    private let analyzer = ImageAnalyzer()

    func removeBackground(from image: UIImage) async -> UIImage? {
        let normalizedImage = image.normalizedForRendering()

        if let liftedSubject = await liftSubjectUsingVisionKit(from: normalizedImage) {
            return liftedSubject
        }

        return await removeWithForegroundMask(from: normalizedImage)
    }

    private func liftSubjectUsingVisionKit(from image: UIImage) async -> UIImage? {
        guard ImageAnalyzer.isSupported else {
            return nil
        }

        do {
            let configuration = ImageAnalyzer.Configuration([.visualLookUp])
            let analysis = try await analyzer.analyze(image, configuration: configuration)

            let interaction = ImageAnalysisInteraction()
            interaction.analysis = analysis
            interaction.preferredInteractionTypes = [.imageSubject]

            let subjects = await interaction.subjects
            guard let subject = subjects.max(by: {
                ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
            }) else {
                return nil
            }

            let liftedImage = try await subject.image

            guard liftedImage.containsTransparentPixels() else {
                return nil
            }

            return liftedImage.normalizedForRendering().croppedToVisibleAlphaBounds()
        } catch {
            return nil
        }
    }

    private func removeWithForegroundMask(from normalizedImage: UIImage) async -> UIImage? {
        guard let cgImage = normalizedImage.cgImage else {
            return nil
        }

        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            guard let result = request.results?.first else {
                return nil
            }

            let maskBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            guard let maskedImage = applyAlphaMask(maskBuffer, to: cgImage, scale: normalizedImage.scale),
                  maskedImage.containsTransparentPixels() else {
                return nil
            }

            return maskedImage.croppedToVisibleAlphaBounds()
        } catch {
            return nil
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
