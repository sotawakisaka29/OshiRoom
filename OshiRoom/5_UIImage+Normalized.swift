import UIKit

extension UIImage {
    /// UIImageの向き情報を実ピクセルへ焼き込み、RealityKitでも同じ向きで扱える画像にします。
    func normalizedForRendering() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func containsTransparentPixels(alphaThreshold: UInt8 = 250) -> Bool {
        guard let alphaValues = renderedAlphaValues() else {
            return false
        }

        return alphaValues.contains { $0 < alphaThreshold }
    }

    func croppedToVisibleAlphaBounds(alphaThreshold: UInt8 = 8) -> UIImage {
        guard let cgImage,
              let alphaValues = renderedAlphaValues(),
              let pixelBounds = visibleAlphaPixelBounds(
                alphaValues: alphaValues,
                width: cgImage.width,
                height: cgImage.height,
                threshold: alphaThreshold
              ),
              let croppedCGImage = cgImage.cropping(to: pixelBounds) else {
            return self
        }

        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)
    }

    func horizontallyMirroredForRendering() -> UIImage {
        let normalizedImage = normalizedForRendering()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = normalizedImage.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: normalizedImage.size, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: normalizedImage.size.width, y: 0)
            cgContext.scaleBy(x: -1, y: 1)
            normalizedImage.draw(in: CGRect(origin: .zero, size: normalizedImage.size))
        }
    }

    private func renderedAlphaValues() -> [UInt8]? {
        guard let cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var alphaValues = [UInt8]()
        alphaValues.reserveCapacity(width * height)

        for pixelIndex in stride(from: 3, to: pixels.count, by: bytesPerPixel) {
            alphaValues.append(pixels[pixelIndex])
        }

        return alphaValues
    }

    private func visibleAlphaPixelBounds(
        alphaValues: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8
    ) -> CGRect? {
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let alpha = alphaValues[y * width + x]
                guard alpha > threshold else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
