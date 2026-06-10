import SwiftUI

/// 初回起動時にアプリの流れを案内するフルスクリーンのチュートリアルです。
struct OnboardingTutorialView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var currentPage = 0

	let onFinished: () -> Void

	private let steps = OnboardingStep.allCases

	var body: some View {
		GeometryReader { proxy in
			let isCompactHeight = proxy.size.height < 760

			ZStack {
				background

				VStack(spacing: isCompactHeight ? 14 : 22) {
					header
						.padding(.horizontal, 24)
						.padding(.top, isCompactHeight ? 14 : 26)

					TabView(selection: $currentPage) {
						ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
							OnboardingStepPage(
								step: step,
								index: index,
								totalCount: steps.count,
								isCompactHeight: isCompactHeight
							)
							.tag(index)
							.padding(.horizontal, 20)
						}
					}
					.tabViewStyle(.page(indexDisplayMode: .never))

					footer
						.padding(.horizontal, 24)
						.padding(.bottom, isCompactHeight ? 14 : 24)
				}
			}
		}
		.interactiveDismissDisabled()
	}

	private var background: some View {
		ZStack {
			LinearGradient(
				colors: [
					Color(red: 0.07, green: 0.08, blue: 0.13),
					Color(red: 0.09, green: 0.12, blue: 0.20),
					Color(red: 0.15, green: 0.11, blue: 0.25)
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)

			Circle()
				.fill(Color(red: 0.98, green: 0.72, blue: 0.30).opacity(0.20))
				.frame(width: 260, height: 260)
				.blur(radius: 10)
				.offset(x: -110, y: -250)

			Circle()
				.fill(Color(red: 0.42, green: 0.74, blue: 0.95).opacity(0.16))
				.frame(width: 300, height: 300)
				.blur(radius: 14)
				.offset(x: 120, y: 220)

			TutorialGrid()
				.stroke(Color.white.opacity(0.06), lineWidth: 1)
		}
		.ignoresSafeArea()
	}

	private var header: some View {
		HStack {
			VStack(alignment: .leading, spacing: 6) {
				Text("Welcome")
					.font(.caption.weight(.semibold))
					.foregroundStyle(Color.white.opacity(0.72))

				Text("My Oshi Room")
					.font(.system(.title2, design: .rounded).weight(.bold))
					.foregroundStyle(.white)
			}

			Spacer()

			Button(currentPage == steps.count - 1 ? "閉じる" : "スキップ") {
				finishTutorial()
			}
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(Color.white.opacity(0.86))
			.padding(.horizontal, 14)
			.padding(.vertical, 10)
			.background(Color.white.opacity(0.10), in: Capsule())
			.overlay(
				Capsule()
					.stroke(Color.white.opacity(0.12), lineWidth: 1)
			)
		}
	}

	private var footer: some View {
		VStack(spacing: 14) {
			HStack(spacing: 8) {
				ForEach(steps.indices, id: \.self) { index in
					Capsule()
						.fill(index == currentPage ? Color.white : Color.white.opacity(0.26))
						.frame(width: index == currentPage ? 26 : 8, height: 8)
						.animation(.easeInOut(duration: 0.22), value: currentPage)
				}
			}

			HStack(spacing: 12) {
				Button("戻る") {
					guard currentPage > 0 else {
						return
					}
					withAnimation(.easeInOut(duration: 0.22)) {
						currentPage -= 1
					}
				}
				.font(.headline)
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.frame(height: 54)
				.background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 20, style: .continuous)
						.stroke(Color.white.opacity(0.12), lineWidth: 1)
				)
				.opacity(currentPage == 0 ? 0.45 : 1)
				.disabled(currentPage == 0)

				Button(currentPage == steps.count - 1 ? "はじめる" : "次へ") {
					if currentPage == steps.count - 1 {
						finishTutorial()
						return
					}

					withAnimation(.easeInOut(duration: 0.22)) {
						currentPage += 1
					}
				}
				.font(.headline.weight(.semibold))
				.foregroundStyle(AppColors.background)
				.frame(maxWidth: .infinity)
				.frame(height: 54)
				.background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
			}
		}
	}

	private func finishTutorial() {
		onFinished()
		dismiss()
	}
}

private struct OnboardingStepPage: View {
	let step: OnboardingStep
	let index: Int
	let totalCount: Int
	let isCompactHeight: Bool

    var body: some View {
        let pageSpacing: CGFloat = isCompactHeight ? 12 : 20
        let cardPadding: CGFloat = isCompactHeight ? 18 : 22
        let titleSpacing: CGFloat = isCompactHeight ? 8 : 10
        let illustrationHeight: CGFloat = {
            switch step {
            case .intro:
                return isCompactHeight ? 150 : 300
            case .room:
                return isCompactHeight ? 180 : 230
            case .shelf:
                return isCompactHeight ? 176 : 224
            case .goods:
                return isCompactHeight ? 148 : 194
            case .edit:
                return isCompactHeight ? 188 : 238
            case .catalog:
                return isCompactHeight ? 176 : 220
            }
        }()
        let pointsInternalTopPadding: CGFloat = 0
        let pointsBoxTopOffset: CGFloat = {
            switch step {
            case .intro:
                return isCompactHeight ? 18 : 24
            case .goods:
                return isCompactHeight ? 18 : 24
            default:
                return isCompactHeight ? 8 : 12
            }
        }()
        let illustrationTopPadding: CGFloat = step == .goods ? (isCompactHeight ? 12 : 16) : 0
        let contentYOffset: CGFloat = step == .intro ? (isCompactHeight ? 10 : 14) : 0

        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: pageSpacing) {
					HStack {
						Text(String(format: "%02d / %02d", index + 1, totalCount))
							.font(.caption.weight(.bold))
							.foregroundStyle(step.accentColor)
							.padding(.horizontal, 12)
							.padding(.vertical, 8)
							.background(step.accentColor.opacity(0.16), in: Capsule())

						Spacer()
					}

					VStack(alignment: .leading, spacing: titleSpacing) {
						Text(step.title)
							.font(.system(isCompactHeight ? .title3 : .largeTitle, design: .rounded).weight(.heavy))
							.foregroundStyle(.white)
							.lineLimit(2)
							.minimumScaleFactor(0.82)

						Text(step.subtitle)
							.font(isCompactHeight ? .subheadline : .body)
							.foregroundStyle(Color.white.opacity(0.76))
							.fixedSize(horizontal: false, vertical: true)
					}
					.frame(maxWidth: .infinity, alignment: .leading)

                    TutorialIllustration(step: step, isCompactHeight: isCompactHeight)
                        .frame(height: illustrationHeight)
                        .padding(.top, illustrationTopPadding)
                        .offset(y: contentYOffset)

                    VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 12) {
                        ForEach(step.points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle")
                                    .font(.caption.weight(.bold))
									.foregroundStyle(step.accentColor)
									.padding(.top, 3)

								Text(point)
									.font(isCompactHeight ? .footnote : .subheadline)
									.foregroundStyle(.white.opacity(0.88))
									.fixedSize(horizontal: false, vertical: true)
							}
						}
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(isCompactHeight ? 16 : 18)
                    .padding(.top, pointsInternalTopPadding)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .padding(.top, pointsBoxTopOffset)
                    .offset(y: contentYOffset)
                }
				.padding(cardPadding)
				.frame(minHeight: proxy.size.height, alignment: .top)
			}
			.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
			.background(
				RoundedRectangle(cornerRadius: 32, style: .continuous)
					.fill(Color.white.opacity(0.06))
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 32, style: .continuous)
					.stroke(Color.white.opacity(0.10), lineWidth: 1)
			)
		}
	}
}

private struct TutorialIllustration: View {
	let step: OnboardingStep
	let isCompactHeight: Bool

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 30, style: .continuous)
				.fill(
					LinearGradient(
						colors: [
							step.accentColor.opacity(0.20),
							Color.white.opacity(0.04)
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
				.overlay(
					RoundedRectangle(cornerRadius: 30, style: .continuous)
						.stroke(Color.white.opacity(0.10), lineWidth: 1)
				)

			switch step {
			case .intro:
				TutorialIntroScene(isCompactHeight: isCompactHeight)
			case .room:
				TutorialRoomScene(accentColor: step.accentColor, isCompactHeight: isCompactHeight)
			case .shelf:
				TutorialShelfScene(accentColor: step.accentColor, isCompactHeight: isCompactHeight)
			case .goods:
				TutorialGoodsScene(accentColor: step.accentColor, isCompactHeight: isCompactHeight)
			case .edit:
				TutorialEditScene(accentColor: step.accentColor, isCompactHeight: isCompactHeight)
			case .catalog:
				TutorialCatalogScene(accentColor: step.accentColor, isCompactHeight: isCompactHeight)
			}
		}
		.clipped()
	}
}

private enum OnboardingStep: CaseIterable {
	case intro
	case room
	case shelf
	case goods
	case edit
	case catalog

	var title: String {
		switch self {
		case .intro:
			return "推しの世界を、ARの部屋に"
		case .room:
			return "最初に部屋を作ります"
		case .shelf:
			return "次にARで棚を置きます"
		case .goods:
			return "写真や3Dモデルを追加します"
		case .edit:
			return "配置したら、あとで調整できます"
		case .catalog:
			return "最後は図鑑で振り返れます"
		}
	}

	var subtitle: String {
		switch self {
		case .intro:
			return "このアプリでは、推しの写真やグッズを自分だけのAR空間に並べて楽しめます。"
		case .room:
			return "ライブや誕生日など、テーマごとに部屋を分けると整理しやすくなります。"
		case .shelf:
			return "床が見つかったら、置きたい場所をタップして棚を配置します。"
		case .goods:
			return "お気に入りの写真は背景を整えて、棚の上にすぐ飾れる形にできます。"
		case .edit:
			return "棚とグッズは、選択して移動・高さ調整・回転・削除ができます。"
		case .catalog:
			return "作ったオブジェクトは図鑑にまとまり、集めた記録を一覧で見返せます。"
		}
	}

	var points: [String] {
		switch self {
		case .intro:
			return [
				"最初は「部屋を作る → 棚を置く → グッズを追加する」の3ステップだけ覚えれば大丈夫です。"
			]
		case .room:
			return [
				"ホーム画面右下の「+」から新しい部屋を作れます。"
			]
		case .shelf:
			return [
				"最初は部屋をゆっくり映して、床を見つけやすくしてください。"
			]
		case .goods:
			return [
				"写真を選ぶ方法と、カメラで撮る方法のどちらでも追加できます。"
			]
		case .edit:
			return [
				"高さ調整や回転、複数選択、削除、元に戻すも下のメニューから行えます。"
			]
		case .catalog:
			return [
				"準備ができたら、最初の部屋を作ってAR空間を始めましょう。"
			]
		}
	}

	var accentColor: Color {
		switch self {
		case .intro:
			return Color(red: 0.98, green: 0.72, blue: 0.30)
		case .room:
			return Color(red: 0.96, green: 0.53, blue: 0.39)
		case .shelf:
			return Color(red: 0.39, green: 0.76, blue: 0.94)
		case .goods:
			return Color(red: 0.98, green: 0.62, blue: 0.26)
		case .edit:
			return Color(red: 0.53, green: 0.82, blue: 0.55)
		case .catalog:
			return Color(red: 0.78, green: 0.62, blue: 0.98)
		}
	}
}

private struct TutorialIntroScene: View {
	let isCompactHeight: Bool

	var body: some View {
		let outerPadding: CGFloat = isCompactHeight ? 16 : 22
		let cardSpacing: CGFloat = isCompactHeight ? 14 : 18
		let outerCardHeight: CGFloat = isCompactHeight ? 184 : 238
		let panelHeight: CGFloat = isCompactHeight ? 94 : 124

		VStack(spacing: isCompactHeight ? 16 : 22) {
			RoundedRectangle(cornerRadius: 30, style: .continuous)
				.fill(Color.white.opacity(0.08))
				.frame(height: outerCardHeight)
				.overlay {
					VStack(spacing: cardSpacing) {
						HStack {
							Spacer()
							Image(systemName: "sparkles")
								.font(.system(size: isCompactHeight ? 20 : 26, weight: .bold))
								.foregroundStyle(.white)
						}

						RoundedRectangle(cornerRadius: 24, style: .continuous)
							.fill(Color(red: 0.40, green: 0.72, blue: 0.96).opacity(0.18))
							.frame(maxWidth: .infinity)
							.frame(height: panelHeight)
							.overlay {
								HStack(spacing: isCompactHeight ? 22 : 30) {
									RoundedRectangle(cornerRadius: 16, style: .continuous)
										.fill(Color(red: 0.98, green: 0.72, blue: 0.30))
										.frame(width: isCompactHeight ? 46 : 58, height: isCompactHeight ? 64 : 80)
										.rotationEffect(.degrees(-10))

									RoundedRectangle(cornerRadius: 16, style: .continuous)
										.fill(Color(red: 0.93, green: 0.48, blue: 0.43))
										.frame(width: isCompactHeight ? 46 : 58, height: isCompactHeight ? 64 : 80)
										.rotationEffect(.degrees(8))
								}
							}

						HStack(spacing: isCompactHeight ? 10 : 12) {
							TutorialMiniTab(label: "ホーム", symbolName: "house.fill")
							TutorialMiniTab(label: "AR", symbolName: "arkit")
							TutorialMiniTab(label: "図鑑", symbolName: "square.grid.2x2.fill")
						}
					}
					.padding(outerPadding)
				}
		}
		.padding(.top, isCompactHeight ? 10 : 14)
		.padding(.horizontal, isCompactHeight ? 14 : 20)
	}
}

private struct TutorialRoomScene: View {
	let accentColor: Color
	let isCompactHeight: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 14) {
			HStack {
				HStack {
					Text("ライブ記念ルーム")
						.font((isCompactHeight ? Font.footnote : .subheadline).weight(.semibold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.minimumScaleFactor(0.78)
					Spacer()
				}
				.padding(.horizontal, isCompactHeight ? 12 : 16)
				.padding(.vertical, isCompactHeight ? 12 : 16)
				.background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

				Image(systemName: "plus.circle.fill")
					.font(isCompactHeight ? .title3 : .title2)
					.foregroundStyle(accentColor)
			}

			HStack(spacing: 12) {
				TutorialPill(text: "思い出ごとに分ける", tint: accentColor)
				TutorialPill(text: "名前だけで作成OK", tint: .white)
			}
		}
		.padding(isCompactHeight ? 16 : 22)
		.background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
		.padding(isCompactHeight ? 10 : 16)
	}
}

private struct TutorialShelfScene: View {
	let accentColor: Color
	let isCompactHeight: Bool

	var body: some View {
		VStack(spacing: isCompactHeight ? 12 : 16) {
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.fill(Color.white.opacity(0.06))
				.frame(height: isCompactHeight ? 128 : 178)
				.overlay {
					VStack(spacing: isCompactHeight ? 10 : 14) {
						RoundedRectangle(cornerRadius: 10, style: .continuous)
							.fill(accentColor)
							.frame(width: isCompactHeight ? 96 : 130, height: isCompactHeight ? 12 : 16)

						HStack(spacing: isCompactHeight ? 38 : 50) {
							RoundedRectangle(cornerRadius: 6, style: .continuous)
								.fill(accentColor.opacity(0.86))
								.frame(width: isCompactHeight ? 10 : 12, height: isCompactHeight ? 52 : 72)
							RoundedRectangle(cornerRadius: 6, style: .continuous)
								.fill(accentColor.opacity(0.86))
								.frame(width: isCompactHeight ? 10 : 12, height: isCompactHeight ? 52 : 72)
						}

						HStack(spacing: 12) {
							TutorialPill(text: "部屋をゆっくり映す", tint: .white)
							TutorialPill(text: "床をタップ", tint: accentColor)
						}
					}
					.padding(isCompactHeight ? 12 : 16)
				}
		}
		.padding(isCompactHeight ? 16 : 22)
		.background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
		.padding(isCompactHeight ? 10 : 16)
	}
}

private struct TutorialGoodsScene: View {
	let accentColor: Color
	let isCompactHeight: Bool

	var body: some View {
		VStack(spacing: isCompactHeight ? 10 : 14) {
			HStack(spacing: isCompactHeight ? 12 : 16) {
				TutorialActionCard(symbolName: "photo.on.rectangle", title: "写真を選択")
				TutorialActionCard(symbolName: "camera.fill", title: "カメラで撮影")
			}

			HStack(spacing: isCompactHeight ? 14 : 20) {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(Color.white.opacity(0.10))
					.frame(width: isCompactHeight ? 66 : 86, height: isCompactHeight ? 64 : 90)
					.overlay(
						Image(systemName: "person.crop.square")
							.font(.system(size: isCompactHeight ? 18 : 26, weight: .light))
							.foregroundStyle(.white.opacity(0.78))
					)

				Image(systemName: "arrow.right")
					.font((isCompactHeight ? Font.title3 : .title3).weight(.bold))
					.foregroundStyle(accentColor)

				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(accentColor)
					.frame(width: isCompactHeight ? 46 : 60, height: isCompactHeight ? 56 : 80)
					.overlay(
						Image(systemName: "sparkles.rectangle.stack")
							.font(.system(size: isCompactHeight ? 16 : 21, weight: .semibold))
							.foregroundStyle(Color.black.opacity(0.70))
					)
			}
		}
		.padding(.horizontal, isCompactHeight ? 18 : 24)
		.padding(.vertical, isCompactHeight ? 12 : 16)
		.background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
		.padding(.horizontal, isCompactHeight ? 14 : 20)
		.padding(.vertical, isCompactHeight ? 10 : 16)
	}
}

private struct TutorialEditScene: View {
	let accentColor: Color
	let isCompactHeight: Bool

	var body: some View {
		VStack(spacing: isCompactHeight ? 12 : 16) {
			HStack(spacing: 10) {
				TutorialEditorChip(title: "棚", symbolName: "shippingbox", isActive: true)
				TutorialEditorChip(title: "グッズ", symbolName: "photo", isActive: false)
				TutorialEditorChip(title: "複数", symbolName: "rectangle.3.group", isActive: false)
			}

			HStack(spacing: 10) {
				TutorialToolButton(title: "高さ調整", symbolName: "arrow.up.and.down", tint: accentColor)
				TutorialToolButton(title: "回転", symbolName: "rotate.3d", tint: .white)
				TutorialToolButton(title: "削除", symbolName: "trash", tint: Color(red: 0.96, green: 0.48, blue: 0.43))
			}
		}
		.padding(isCompactHeight ? 16 : 22)
		.background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
		.padding(isCompactHeight ? 10 : 16)
	}
}

private struct TutorialCatalogScene: View {
	let accentColor: Color
	let isCompactHeight: Bool

	var body: some View {
		VStack(spacing: isCompactHeight ? 12 : 16) {
			HStack(spacing: 10) {
				ForEach(0..<3) { _ in
					RoundedRectangle(cornerRadius: 18, style: .continuous)
						.fill(Color.white.opacity(0.09))
						.frame(height: isCompactHeight ? 70 : 92)
						.overlay(
							RoundedRectangle(cornerRadius: 14, style: .continuous)
								.fill(accentColor.opacity(0.78))
								.padding(isCompactHeight ? 8 : 10)
						)
				}
			}

			HStack(spacing: 12) {
				TutorialBadge(label: "部屋ごとに整理", symbolName: "door.left.hand.open")
				TutorialBadge(label: "図鑑で一覧", symbolName: "square.grid.2x2.fill")
			}
		}
		.padding(isCompactHeight ? 16 : 22)
		.background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
		.padding(isCompactHeight ? 10 : 16)
	}
}

private struct TutorialBadge: View {
	let label: String
	let symbolName: String

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: symbolName)
			Text(label)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
		}
		.font(.caption.weight(.semibold))
		.foregroundStyle(.white)
		.padding(.horizontal, 12)
		.padding(.vertical, 9)
		.background(Color.white.opacity(0.10), in: Capsule())
	}
}

private struct TutorialMiniTab: View {
	let label: String
	let symbolName: String

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: symbolName)
			Text(label)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
		}
		.font(.caption2.weight(.semibold))
		.foregroundStyle(.white)
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity)
		.background(Color.white.opacity(0.08), in: Capsule())
	}
}

private struct TutorialPill: View {
	let text: String
	let tint: Color

	var body: some View {
		Text(text)
			.font(.caption.weight(.semibold))
			.foregroundStyle(.white)
			.lineLimit(1)
			.minimumScaleFactor(0.58)
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.frame(maxWidth: .infinity)
			.background(tint.opacity(0.16), in: Capsule())
			.overlay(
				Capsule()
					.stroke(tint.opacity(0.28), lineWidth: 1)
			)
	}
}

private struct TutorialActionCard: View {
	let symbolName: String
	let title: String

	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: symbolName)
				.font(.title3.weight(.semibold))
				.foregroundStyle(.white)

			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.white)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
		.frame(maxWidth: .infinity)
		.frame(height: 80)
		.background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.stroke(Color.white.opacity(0.10), lineWidth: 1)
		)
	}
}

private struct TutorialEditorChip: View {
	let title: String
	let symbolName: String
	let isActive: Bool

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: symbolName)
			Text(title)
				.lineLimit(1)
				.minimumScaleFactor(0.55)
		}
		.font(.caption.weight(.semibold))
		.foregroundStyle(isActive ? AppColors.background : .white)
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.frame(maxWidth: .infinity)
		.background(isActive ? Color.white : Color.white.opacity(0.08), in: Capsule())
	}
}

private struct TutorialToolButton: View {
	let title: String
	let symbolName: String
	let tint: Color

	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: symbolName)
				.font(.headline)
			Text(title)
				.font(.caption2.weight(.bold))
				.lineLimit(1)
				.minimumScaleFactor(0.7)
		}
		.foregroundStyle(tint)
		.frame(maxWidth: .infinity)
		.frame(height: 74)
		.background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(Color.white.opacity(0.10), lineWidth: 1)
		)
	}
}

private struct TutorialGrid: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		let spacing: CGFloat = 28

		var x: CGFloat = 0
		while x <= rect.width {
			path.move(to: CGPoint(x: x, y: 0))
			path.addLine(to: CGPoint(x: x, y: rect.height))
			x += spacing
		}
		
		var y: CGFloat = 0
		while y <= rect.height {
			path.move(to: CGPoint(x: 0, y: y))
			path.addLine(to: CGPoint(x: rect.width, y: y))
			y += spacing
		}

		return path
	}
}

#Preview {
	OnboardingTutorialView(onFinished: {})
}
