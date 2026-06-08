import SwiftData
import SwiftUI

/// アプリ全体の入口になる画面です。
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }

            EncyclopediaView()
                .tabItem {
                    Label("図鑑", systemImage: "square.grid.2x2.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewModelContainer.make())
}

/// 15秒のプロモーション映像の土台になる画面です。
struct PromotionLaunchView: View {
    private let duration: Double = 15
    @State private var startDate = Date()

    private let demoRoom: Room = {
        let room = Room(name: "ライブ記念ルーム", displayOrder: 0)
        let shelf = Shelf(name: "メイン棚", template: .wood, room: room)
        room.shelves = [shelf]
        room.updatedAt = .now
        return room
    }()

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let playhead = elapsed.truncatingRemainder(dividingBy: duration)

            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    promoBackground(elapsed: playhead, size: size)
                        .ignoresSafeArea()

                    sceneHero(elapsed: playhead, size: size)
                        .opacity(sceneOpacity(elapsed: playhead, start: 0.0, end: 4.1))

                    sceneCreateRoom(elapsed: playhead, size: size)
                        .opacity(sceneOpacity(elapsed: playhead, start: 3.4, end: 7.7))

                    sceneAddGoods(elapsed: playhead, size: size)
                        .opacity(sceneOpacity(elapsed: playhead, start: 7.0, end: 11.6))

                    sceneFinal(elapsed: playhead, size: size)
                        .opacity(sceneOpacity(elapsed: playhead, start: 11.0, end: 15.0))

                    promoProgressBar(elapsed: playhead)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)
                }
            }
        }
    }

    private func promoBackground(elapsed: Double, size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.14, green: 0.10, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            BackgroundGrid()
                .opacity(0.24)

            FloatingGlow(
                color: Color(red: 0.98, green: 0.70, blue: 0.26),
                size: 220,
                x: size.width * 0.16 + CGFloat(sin(elapsed * 0.75)) * 18,
                y: size.height * 0.22 + CGFloat(cos(elapsed * 0.62)) * 10,
                opacity: 0.34
            )

            FloatingGlow(
                color: Color(red: 0.40, green: 0.72, blue: 0.96),
                size: 260,
                x: size.width * 0.82 + CGFloat(cos(elapsed * 0.48)) * 20,
                y: size.height * 0.20 + CGFloat(sin(elapsed * 0.51)) * 14,
                opacity: 0.26
            )

            FloatingGlow(
                color: Color(red: 0.71, green: 0.48, blue: 0.98),
                size: 300,
                x: size.width * 0.70 + CGFloat(sin(elapsed * 0.32)) * 26,
                y: size.height * 0.78 + CGFloat(cos(elapsed * 0.40)) * 16,
                opacity: 0.22
            )
        }
    }

    private func sceneHero(elapsed: Double, size: CGSize) -> some View {
        let titleOffset = CGFloat(1 - easeInOut(clamp(elapsed / 1.0))) * 24
        let intro = easeInOut(clamp((elapsed - 0.4) / 1.6))

        return VStack(spacing: 22) {
            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Text("AR空間に")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                Text("自分の好きな世界が広がる")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                Text("推しの写真、グッズ、3Dモデルを\nひとつの部屋にまとめて飾れます。")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .offset(y: titleOffset)
            .scaleEffect(0.94 + 0.06 * intro)
            .padding(.horizontal, 26)

            PromoRoomIllustration(progress: intro)
                .frame(height: min(size.height * 0.40, 320))
                .padding(.horizontal, 18)
                .opacity(0.95)

            PromoBadgeRow(
                title: "My Oshi Room",
                subtitle: "App Storeではこの名前で表示されます。"
            )
            .padding(.horizontal, 26)
            .opacity(0.92 + 0.08 * intro)

            Spacer(minLength: 20)
        }
    }

    private func sceneCreateRoom(elapsed: Double, size: CGSize) -> some View {
        let stage = easeInOut(clamp((elapsed - 3.55) / 1.45))
        let slide = CGFloat(1 - stage) * 30

        return VStack(spacing: 18) {
            Spacer(minLength: 18)

            PromoSectionHeader(
                step: "01 / 04",
                title: "まずは部屋を作る",
                subtitle: "部屋名をつけるだけで、AR空間の土台ができます。"
            )
            .offset(y: slide)
            .padding(.horizontal, 24)

            RoomCardView(
                room: demoRoom,
                action: {},
                renameAction: {},
                objectListAction: {}
            )
            .padding(.horizontal, 20)
            .scaleEffect(0.98 + 0.02 * stage)
            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)

            VStack(spacing: 12) {
                Text("「ライブ記念ルーム」みたいに、\n思い出ごとに分けて整理できます。")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(ShelfTemplate.allCases) { template in
                        ShelfTemplateRow(template: template, isSelected: template == .wood) {
                            // プロモーション映像では選択操作は見せるだけにします。
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 10)
        }
    }

    private func sceneAddGoods(elapsed: Double, size: CGSize) -> some View {
        let stage = easeInOut(clamp((elapsed - 7.15) / 1.55))
        let width = min(size.width - 36, 420)

        return VStack(spacing: 16) {
            Spacer(minLength: 18)

            PromoSectionHeader(
                step: "02 / 04",
                title: "写真から、すぐグッズ化",
                subtitle: "カメラや写真を使って、推しのグッズを部屋に追加できます。"
            )
            .padding(.horizontal, 24)
            .opacity(0.95 + 0.05 * stage)

            HStack(spacing: 14) {
                AddGoodsActionPreview(
                    icon: "photo.on.rectangle",
                    title: "写真を選択",
                    subtitle: "お気に入りの一枚から"
                )

                AddGoodsActionPreview(
                    icon: "camera",
                    title: "カメラで撮影",
                    subtitle: "今この瞬間を残す"
                )
            }
            .frame(width: width)
            .padding(.horizontal, 18)

            ZStack(alignment: .bottomTrailing) {
                PromoCutoutCard(progress: stage)
                    .frame(height: 220)

                PromoMiniBubble(
                    text: "背景除去で\nアクスタ風に",
                    symbol: "sparkles",
                    color: Color(red: 0.98, green: 0.70, blue: 0.26)
                )
                .offset(x: -18, y: 16)
                .opacity(0.96)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                AddGoodsActionPreview(
                    icon: "cube.transparent",
                    title: "3Dモデルを選択",
                    subtitle: "スキャン済みモデルも飾れる"
                )
                .frame(width: width)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 8)
        }
    }

    private func sceneFinal(elapsed: Double, size: CGSize) -> some View {
        let stage = easeInOut(clamp((elapsed - 11.1) / 1.4))
        let headlineShift = CGFloat(1 - stage) * 18

        return VStack(spacing: 18) {
            Spacer(minLength: 20)

            PromoBadgeRow(
                title: "My Oshi Room",
                subtitle: "AR空間に、好きな世界を育てよう。"
            )
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Text("部屋、グッズ、3Dモデルをひとつに。")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .offset(y: headlineShift)

                Text("推し活が、そのまま飾れるAR体験になります。")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .padding(.horizontal, 22)

            PromoRoomIllustration(progress: 0.92)
                .frame(height: min(size.height * 0.36, 300))
                .padding(.horizontal, 22)

            VStack(spacing: 12) {
                PromoFinalCTA(title: "My Oshi Room", subtitle: "App Storeで会いましょう")
                Text("AR空間に自分の好きな世界が広がる")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 18)
        }
    }

    private func promoProgressBar(elapsed: Double) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("0:15")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text("My Oshi Room")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.70, blue: 0.26),
                                        Color(red: 0.40, green: 0.72, blue: 0.96)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * clamp(elapsed / duration))
                    }
            }
            .frame(height: 6)
        }
    }

    private func sceneOpacity(elapsed: Double, start: Double, end: Double) -> Double {
        let fade: Double = 0.35

        if elapsed < start - fade || elapsed > end + fade {
            return 0
        }

        if elapsed < start {
            return easeInOut(clamp((elapsed - (start - fade)) / fade))
        }

        if elapsed > end {
            return 1 - easeInOut(clamp((elapsed - end) / fade))
        }

        return 1
    }

    private func clamp(_ value: Double) -> Double {
        Swift.max(0, Swift.min(1, value))
    }

    private func easeInOut(_ value: Double) -> Double {
        let clamped = clamp(value)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// 背景のやわらかい格子です。
private struct BackgroundGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, canvasSize in
                var path = Path()
                let horizontalStep: CGFloat = max(28, canvasSize.height / 12)
                let verticalStep: CGFloat = max(28, canvasSize.width / 10)

                for x in stride(from: 0, through: canvasSize.width, by: verticalStep) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                }

                for y in stride(from: 0, through: canvasSize.height, by: horizontalStep) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                }

                context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// ふわっと漂う発光です。
private struct FloatingGlow: View {
    let color: Color
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let opacity: Double

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.25)
            .opacity(opacity)
            .position(x: x, y: y)
            .blendMode(.screen)
    }
}

/// 最初の印象を作るARルームのイラストです。
private struct PromoRoomIllustration: View {
    let progress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .frame(height: 56)
                    .overlay {
                        Text("AR Shelf")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.horizontal, 28)
                    .offset(y: -8)

                HStack(spacing: 16) {
                    PromoCardStack(
                        title: "写真から",
                        subtitle: "アクスタ風に",
                        icon: "photo",
                        color: Color(red: 0.98, green: 0.70, blue: 0.26),
                        progress: progress
                    )

                    PromoCardStack(
                        title: "3Dモデル",
                        subtitle: "そのまま飾る",
                        icon: "cube.transparent",
                        color: Color(red: 0.40, green: 0.72, blue: 0.96),
                        progress: 1 - progress * 0.25
                    )
                }
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    ForEach(ShelfTemplate.allCases) { template in
                        VStack(spacing: 8) {
                            Image(systemName: template.symbolName)
                                .font(.headline)
                                .foregroundStyle(template.tint)
                                .frame(width: 38, height: 38)
                                .background(template.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(template.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 26)
                .offset(y: progress * -2)
            }
            .padding(.vertical, 18)
        }
    }
}

/// RoomCardViewの雰囲気を支えるカードです。
private struct PromoCardStack: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
            }

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.95),
                            color.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 90)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .offset(y: 6 * (1 - progress))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// 各シーンの説明をまとめる見出しです。
private struct PromoSectionHeader: View {
    let step: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.58))

            Text(title)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// グッズ追加画面のボタンを見せるためのカードです。
private struct AddGoodsActionPreview: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.70))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

/// 透過背景のついたグッズを見せるカードです。
private struct PromoCutoutCard: View {
    let progress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.93, blue: 0.80),
                            Color(red: 0.92, green: 0.78, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )

            Circle()
                .fill(Color.white.opacity(0.26))
                .frame(width: 84, height: 84)
                .offset(x: -58, y: -40)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.98, green: 0.70, blue: 0.26))
                .frame(width: 132, height: 184)
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white.opacity(0.94))

                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.50))
                            .frame(width: 76, height: 108)
                            .overlay {
                                Text("Oshi")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color(red: 0.58, green: 0.30, blue: 0.10))
                            }
                    }
                }
                .rotationEffect(.degrees(-6 + 8 * (1 - progress)))
                .offset(x: -26 + 18 * progress, y: -10 + 8 * (1 - progress))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 2)
                .frame(width: 180, height: 112)
                .rotationEffect(.degrees(10))
                .offset(x: 42, y: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text("背景除去")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.56))
                Text("アクスタ風の\nグッズが完成")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.black.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 26)
            .offset(y: 58)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }
}

/// 最後に見せる締めのカードです。
private struct PromoFinalCTA: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.70, blue: 0.26).opacity(0.24),
                    Color(red: 0.40, green: 0.72, blue: 0.96).opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

/// ブランド名をやわらかく見せるバッジです。
private struct PromoBadgeRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// 小さな吹き出しです。
private struct PromoMiniBubble: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

#Preview("Promotion") {
    PromotionLaunchView()
}
