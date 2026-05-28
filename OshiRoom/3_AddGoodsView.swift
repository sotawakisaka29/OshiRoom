import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// 写真を選択し、背景除去済みグッズを作成する画面です。
struct AddGoodsView: View {
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \ScannedModel.updatedAt, order: .reverse) private var scannedModels: [ScannedModel]
	@State private var viewModel = AddGoodsViewModel()
	@State private var isShowingCamera = false
	@State private var isShowingModelSelection = false
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
			VStack(spacing: 24) {
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

				preview

				VStack(spacing: 12) {
					PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
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

				if viewModel.isProcessing {
					ProgressView("作成中")
						.padding(.top, 4)
				}

				Spacer()
			}
			.padding(22)
			.background(AppColors.groupedBackground.ignoresSafeArea())
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("閉じる") {
						dismiss()
					}
				}
			}
			.onChange(of: viewModel.selectedItem) { _, _ in
				Task {
					if let result = await viewModel.loadSelectedImage() {
						onCreated(result.0, result.1)
					}
				}
			}
			.fullScreenCover(isPresented: $isShowingCamera) {
				CameraCaptureView { image in
					isShowingCamera = false
					Task {
						if let result = await viewModel.processCapturedImage(image) {
							onCreated(result.0, result.1)
						}
					}
				} onCancel: {
					isShowingCamera = false
				}
				.ignoresSafeArea()
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

	@ViewBuilder
	private var preview: some View {
		if let image = viewModel.previewImage {
			Image(uiImage: image)
				.resizable()
				.scaledToFit()
				.frame(maxHeight: 260)
				.frame(maxWidth: .infinity)
				.padding(24)
				.background(AppColors.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 28, style: .continuous)
						.stroke(AppColors.separator, lineWidth: 1)
				)
		} else {
			VStack(spacing: 14) {
				Image(systemName: "person.crop.square")
					.font(.system(size: 44, weight: .light))
					.foregroundStyle(AppColors.textSecondary)
				Text("背景除去後のプレビューがここに表示されます。")
					.font(.subheadline)
					.foregroundStyle(AppColors.textSecondary)
			}
			.frame(maxWidth: .infinity)
			.frame(height: 260)
			.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.stroke(AppColors.separator, lineWidth: 1)
			)
		}
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

#Preview {
	AddGoodsView { _, _ in }
}
