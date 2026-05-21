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
}
