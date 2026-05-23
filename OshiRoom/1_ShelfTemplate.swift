import SwiftUI

/// ARに置く棚の見た目テンプレートです。
enum ShelfTemplate: String, CaseIterable, Codable, Identifiable {
    case wood
    case glass
    case wall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wood:
            "木製棚"
        case .glass:
            "ガラスケース"
        case .wall:
            "壁掛け棚"
        }
    }

    var subtitle: String {
        switch self {
        case .wood:
            "あたたかい木目風の展示棚"
        case .glass:
            "透明感のあるコレクションケース"
        case .wall:
            "省スペースな壁面ディスプレイ"
        }
    }

    var symbolName: String {
        switch self {
        case .wood:
            "books.vertical"
        case .glass:
            "shippingbox"
        case .wall:
            "rectangle.portrait.on.rectangle.portrait"
        }
    }

    var tint: Color {
        switch self {
        case .wood:
            Color(red: 0.58, green: 0.42, blue: 0.28)
        case .glass:
            Color(red: 0.48, green: 0.66, blue: 0.78)
        case .wall:
            Color(red: 0.54, green: 0.56, blue: 0.60)
        }
    }
}
