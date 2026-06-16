import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// 写真を選択し、背景除去の有無を切り替えながらグッズを作成する画面です。
struct AddGoodsView: View {
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \ScannedModel.updatedAt, order: .reverse) private var scannedModels: [ScannedModel]
	@State private var viewModel = AddGoodsViewModel()
	@State private var isShowingPhotoPicker = false
	@State private var isShowingCamera = false
	@State private var isShowingModelSelection = false
	@State private var isPreviewLifted = false
	let onCreated: (UIImage, String) -> Void
	let onModelSelected: (ScannedModel) -> Void

	init(
		onCreated: @escaping (UIImage, String) -> Void,
		onModelSelected: @escaping (ScannedModel) -> Void = { _ in }
	) {
		self.onCreated = onCreated
		self.onModelSelected = onModelSelected
	}

	var body: some View {
		@Bindable var viewModel = viewModel

		NavigationStack {
			GeometryReader { proxy in
				ScrollView {
					VStack(spacing: 20) {
						VStack(spacing: 10) {
							Text("グッズ追加")
								.font(.system(.largeTitle, design: .rounded).weight(.bold))
								.foregroundStyle(AppColors.textPrimary)
							Text(viewModel.message)
								.font(.callout)
								.foregroundStyle(AppColors.textSecondary)
								.multilineTextAlignment(.center)
								.padding(.horizontal)
						}

						VStack(alignment: .leading, spacing: 10) {
							HStack(spacing: 10) {
								Image(systemName: "person.crop.square")
									.font(.headline.weight(.semibold))
									.foregroundStyle(AppColors.textPrimary)

								VStack(alignment: .leading, spacing: 2) {
									Text("背景を削除")
										.font(.headline)
										.foregroundStyle(AppColors.textPrimary)
									Text(viewModel.shouldRemoveBackground ? "被写体だけを抽出します" : "写真の背景も残します")
										.font(.caption)
										.foregroundStyle(AppColors.textSecondary)
								}

								Spacer()

								Toggle("", isOn: $viewModel.shouldRemoveBackground)
									.labelsHidden()
									.toggleStyle(.switch)
									.disabled(viewModel.isProcessing)
							}

							Text("オンにすると被写体だけを切り抜いて、オフにすると写真の背景を残したまま保存します。")
								.font(.footnote)
								.foregroundStyle(AppColors.textSecondary)
								.fixedSize(horizontal: false, vertical: true)
						}
						.padding(16)
						.frame(maxWidth: .infinity, alignment: .leading)
						.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 22, style: .continuous)
								.stroke(AppColors.separator, lineWidth: 1)
						)

						preview(availableHeight: proxy.size.height)

						if isShowingPreparedPhotoState {
							VStack(spacing: 12) {
								Button {
									guard let result = viewModel.commitPreparedGoods() else {
										return
									}

									onCreated(result.0, result.1)
									dismiss()
								} label: {
									Label("追加する", systemImage: "checkmark.circle.fill")
										.font(.headline)
										.foregroundStyle(AppColors.background)
										.frame(maxWidth: .infinity)
										.frame(height: 56)
										.background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
								}
								.disabled(viewModel.previewImage == nil || viewModel.pendingImagePath == nil || viewModel.isProcessing)
								.opacity(viewModel.previewImage == nil || viewModel.pendingImagePath == nil || viewModel.isProcessing ? 0.5 : 1)

								Button {
									isPreviewLifted = false
									isShowingPhotoPicker = true
									viewModel.resetSelectedImage()
								} label: {
									Label("選び直す", systemImage: "arrow.counterclockwise")
										.font(.headline)
										.foregroundStyle(AppColors.textPrimary)
										.frame(maxWidth: .infinity)
										.frame(height: 56)
										.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
										.overlay(
											RoundedRectangle(cornerRadius: 20, style: .continuous)
												.stroke(AppColors.separator, lineWidth: 1)
										)
								}
								.disabled(viewModel.isProcessing)
							}
						} else {
							VStack(spacing: 12) {
								Button {
									isShowingPhotoPicker = true
								} label: {
									Label("写真を選択", systemImage: "photo.on.rectangle")
										.font(.headline)
										.foregroundStyle(AppColors.background)
										.frame(maxWidth: .infinity)
										.frame(height: 56)
										.background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
								}
								.disabled(viewModel.isProcessing)

								Button {
									if canUseCamera {
										isShowingCamera = true
									} else {
										viewModel.message = "この端末ではカメラを利用できません。写真選択を使ってください。"
									}
								} label: {
									Label("カメラで撮影", systemImage: "camera")
										.font(.headline)
										.foregroundStyle(AppColors.textPrimary)
										.frame(maxWidth: .infinity)
										.frame(height: 56)
										.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
										.overlay(
											RoundedRectangle(cornerRadius: 20, style: .continuous)
												.stroke(AppColors.separator, lineWidth: 1)
										)
								}
								.disabled(viewModel.isProcessing)

								Button {
									isShowingModelSelection = true
								} label: {
									Label("3Dモデルを選択", systemImage: "cube")
										.font(.headline)
										.foregroundStyle(AppColors.textPrimary)
										.frame(maxWidth: .infinity)
										.frame(height: 56)
										.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
										.overlay(
											RoundedRectangle(cornerRadius: 20, style: .continuous)
												.stroke(AppColors.separator, lineWidth: 1)
										)
								}
								.disabled(availableModels.isEmpty || viewModel.isProcessing)
							}
						}

						if viewModel.isProcessing {
							ProgressView("作成中")
								.padding(.top, 4)
						}
					}
					.padding(22)
					.frame(maxWidth: .infinity, alignment: .top)
					.frame(minHeight: proxy.size.height, alignment: .top)
				}
			}
			.background(AppColors.groupedBackground.ignoresSafeArea())
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("閉じる") {
						dismiss()
					}
				}
			}
			.onChange(of: viewModel.shouldRemoveBackground) { _, _ in
				isPreviewLifted = false
				Task {
					await viewModel.reprocessCurrentImage()
				}
			}
			.onChange(of: viewModel.isProcessing) { _, isProcessing in
				if isProcessing {
					isPreviewLifted = false
				}
			}
			.fullScreenCover(isPresented: $isShowingCamera) {
				CameraCaptureView { image in
					isShowingCamera = false
					Task {
						await viewModel.processCapturedImage(image)
					}
				} onCancel: {
					isShowingCamera = false
				}
				.ignoresSafeArea()
			}
			.sheet(isPresented: $isShowingPhotoPicker) {
				PhotoPickerSheet { image in
					isShowingPhotoPicker = false
					Task {
						await viewModel.processPickedImage(image)
					}
				} onCancel: {
					isShowingPhotoPicker = false
				}
			}
			.sheet(isPresented: $isShowingModelSelection) {
				ScannedModelPickerView(models: availableModels) { model in
					onModelSelected(model)
					isShowingModelSelection = false
					dismiss()
				}
				.presentationDetents([.medium, .large])
			}
		}
	}

	private var availableModels: [ScannedModel] {
		scannedModels.filter { $0.modelPath != nil }
	}

	private var canUseCamera: Bool {
		UIImagePickerController.isSourceTypeAvailable(.camera)
	}

	private var isShowingPreparedPhotoState: Bool {
		viewModel.previewImage != nil || viewModel.pendingImagePath != nil || viewModel.isProcessing
	}

	@ViewBuilder
	private func preview(availableHeight: CGFloat) -> some View {
		let previewHeight: CGFloat = if isShowingPreparedPhotoState {
			min(max(availableHeight * 0.56, 420), 620)
		} else {
			min(max(availableHeight * 0.2, 160), 220)
		}

		VStack(spacing: 16) {
			HStack {
				Text("プレビュー")
					.font(.headline.weight(.semibold))
					.foregroundStyle(AppColors.textPrimary)
				Spacer()
				if viewModel.isProcessing {
					Label("作成中", systemImage: "hourglass")
						.font(.caption.weight(.semibold))
						.foregroundStyle(AppColors.textSecondary)
				}
			}

			Group {
				if let image = viewModel.previewImage {
					liftablePreview(image: image, previewHeight: previewHeight)
				} else {
					VStack(spacing: 14) {
						Image(systemName: "person.crop.square")
							.font(.system(size: 44, weight: .light))
							.foregroundStyle(AppColors.textSecondary)
						Text(viewModel.isProcessing ? "プレビューを作成中です。" : "プレビューがここに表示されます。")
							.font(.subheadline)
							.foregroundStyle(AppColors.textSecondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.frame(height: previewHeight)
					.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 28, style: .continuous)
							.stroke(AppColors.separator, lineWidth: 1)
					)
				}
			}
		}
	}

	@ViewBuilder
	private func liftablePreview(image: UIImage, previewHeight: CGFloat) -> some View {
		let shouldAnimateLift = isPreviewLifted && !viewModel.isProcessing

		ZStack(alignment: .topLeading) {
			Image(uiImage: image)
				.resizable()
				.scaledToFit()
				.frame(maxHeight: previewHeight)
				.frame(maxWidth: .infinity)
				.padding(18)
				.background(
					LinearGradient(
						colors: [
							AppColors.background,
							AppColors.elevatedSurface
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					),
					in: RoundedRectangle(cornerRadius: 28, style: .continuous)
				)
				.overlay(
					RoundedRectangle(cornerRadius: 28, style: .continuous)
						.stroke(shouldAnimateLift ? AppColors.textPrimary.opacity(0.24) : AppColors.textPrimary.opacity(0.14), lineWidth: shouldAnimateLift ? 2 : 1.5)
				)
				.shadow(color: AppColors.textPrimary.opacity(shouldAnimateLift ? 0.18 : 0.08), radius: shouldAnimateLift ? 24 : 16, x: 0, y: shouldAnimateLift ? 14 : 8)
				.scaleEffect(shouldAnimateLift ? 1.03 : 1.0)
				.offset(y: shouldAnimateLift ? -8 : 0)
				.rotationEffect(.degrees(shouldAnimateLift ? -1.2 : 0))

			Text(viewModel.shouldRemoveBackground ? "長押しで被写体を持ち上げる" : "背景あり")
				.font(.caption.weight(.semibold))
				.foregroundStyle(AppColors.textSecondary)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.background(.ultraThinMaterial, in: Capsule())
				.padding(12)
		}
		.frame(maxWidth: .infinity, alignment: .center)
		.contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
		.onLongPressGesture(minimumDuration: 0.35, maximumDistance: 60, pressing: { isPressing in
			guard !viewModel.isProcessing else {
				return
			}

			withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
				isPreviewLifted = isPressing
			}

			if isPressing {
				UIImpactFeedbackGenerator(style: .soft).impactOccurred()
			}
		}, perform: {
			guard !viewModel.isProcessing else {
				return
			}

			withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
				isPreviewLifted = false
			}
		})
	}
}

struct ScannedModelPickerView: View {
	@Environment(\.dismiss) private var dismiss
	let models: [ScannedModel]
	let onSelect: (ScannedModel) -> Void

	var body: some View {
		NavigationStack {
			Group {
				if models.isEmpty {
					VStack(spacing: 12) {
						Image(systemName: "cube.transparent")
							.font(.system(size: 42, weight: .light))
							.foregroundStyle(AppColors.textSecondary)
						Text("選択できる3Dモデルがありません")
							.font(.headline)
							.foregroundStyle(AppColors.textPrimary)
						Text("先に3Dモデルを生成してください。")
							.font(.subheadline)
							.foregroundStyle(AppColors.textSecondary)
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(AppColors.groupedBackground)
				} else {
					List {
						ForEach(models) { model in
							Button {
								onSelect(model)
							} label: {
								HStack(spacing: 16) {
									if let thumbnailData = model.previewThumbnailData,
										 let image = UIImage(data: thumbnailData) {
										Image(uiImage: image)
											.resizable()
											.scaledToFill()
											.frame(width: 68, height: 76)
											.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
									} else {
										Image(systemName: model.method.symbolName)
											.font(.title3.weight(.semibold))
											.foregroundStyle(AppColors.background)
											.frame(width: 68, height: 76)
											.background(
												{
													switch model.method {
													case .lidar:
														Color.blue
													case .photogrammetry:
														Color.orange
													case .objectCapture:
														Color.indigo
													case .trueDepth:
														Color.green
													}
												}(),
												in: RoundedRectangle(cornerRadius: 18, style: .continuous)
											)
									}

									VStack(alignment: .leading, spacing: 5) {
										Text(model.name)
											.font(.headline)
											.foregroundStyle(AppColors.textPrimary)
										Text(model.updatedAt.formatted(date: .abbreviated, time: .shortened))
											.font(.caption)
											.foregroundStyle(AppColors.textMuted)
									}

									Spacer()

									Image(systemName: "chevron.right")
										.font(.footnote.weight(.semibold))
										.foregroundStyle(AppColors.textMuted)
								}
								.frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
								.padding(.vertical, 12)
							}
							.buttonStyle(.plain)
							.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
						}
					}
					.listStyle(.plain)
					.scrollContentBackground(.hidden)
					.background(AppColors.groupedBackground)
				}
			}
			.navigationTitle("3Dモデルを選択")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("閉じる") {
						dismiss()
					}
				}
			}
		}
	}
}

struct PhotoPickerSheet: UIViewControllerRepresentable {
	@Environment(\.dismiss) private var dismiss
	let onPick: (UIImage) -> Void
	let onCancel: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(onPick: onPick, onCancel: onCancel)
	}

	func makeUIViewController(context: Context) -> PHPickerViewController {
		var configuration = PHPickerConfiguration(photoLibrary: .shared())
		configuration.filter = .images
		configuration.selectionLimit = 1

		let picker = PHPickerViewController(configuration: configuration)
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

	final class Coordinator: NSObject, PHPickerViewControllerDelegate {
		let onPick: (UIImage) -> Void
		let onCancel: () -> Void

		init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
			self.onPick = onPick
			self.onCancel = onCancel
		}

		func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
			guard let result = results.first else {
				onCancel()
				return
			}

			let provider = result.itemProvider
			guard provider.canLoadObject(ofClass: UIImage.self) else {
				onCancel()
				return
			}

			provider.loadObject(ofClass: UIImage.self) { object, _ in
				guard let image = object as? UIImage else {
					DispatchQueue.main.async {
						self.onCancel()
					}
					return
				}

				DispatchQueue.main.async {
					self.onPick(image)
				}
			}
		}
	}
}

#Preview {
	AddGoodsView { _, _ in }
}
