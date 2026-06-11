import SwiftData
import SwiftUI
import UIKit

/// スキャン済み3Dモデルの一覧画面です。
struct ScannedModelsView: View {
	@Environment(\.modelContext) private var modelContext
	@Query private var models: [ScannedModel]
	@State private var selectedModel: ScannedModel?
	@State private var inlineEditingModelID: ScannedModel.ID?
	@State private var inlineEditedModelName = ""
	@State private var inlineOriginalModelName = ""
	@State private var deleteTargetModel: ScannedModel?
	@State private var isShowingDeleteAlert = false
	@FocusState private var focusedEditingModelID: ScannedModel.ID?
	@State private var isShowingModelScanner = false
	@State private var isShowingHelpTips = false
	@State private var sortOption: ScannedModelSortOption = .addedDate
	@State private var sortDirection: ScannedModelSortDirection = .descending

	var body: some View {
		let displayedModels = sortedModels()

		ZStack {
			Group {
				if displayedModels.isEmpty {
					emptyState
				} else {
					List {
						ForEach(displayedModels) { model in
							row(for: model)
							.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
						}
					}
					.listStyle(.plain)
					.scrollContentBackground(.hidden)
					.background(AppColors.groupedBackground)
				}
			}
			.toolbar(isShowingHelpTips ? .hidden : .visible, for: .navigationBar)
			.overlay {
				if isShowingHelpTips {
					ScannedModelsTipsOverlay {
						withAnimation(.snappy(duration: 0.22)) {
							isShowingHelpTips = false
						}
					}
				}
			}
		}
		.navigationTitle("3Dモデル")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .topBarTrailing) {
				Menu {
					Picker("並び替え", selection: $sortOption) {
						ForEach(ScannedModelSortOption.allCases) { option in
							Text(option.title).tag(option)
						}
					}

					Picker("順序", selection: $sortDirection) {
						ForEach(ScannedModelSortDirection.allCases) { direction in
							Text(direction.title).tag(direction)
						}
					}
				} label: {
					Image(systemName: "arrow.up.arrow.down")
				}

				Button {
					withAnimation(.snappy(duration: 0.22)) {
						isShowingHelpTips = true
					}
				} label: {
					Image(systemName: "questionmark.circle")
				}
				.accessibilityLabel("ヘルプ")

				Button {
					isShowingModelScanner = true
				} label: {
					Image(systemName: "camera.viewfinder")
				}
				.accessibilityLabel("物体スキャン")
			}
		}
		.sheet(isPresented: $isShowingModelScanner) {
			ModelScanView()
				.presentationDetents([.large])
		}
		.navigationDestination(item: $selectedModel) { model in
			ScannedModelPreviewView(model: model)
		}
		.alert("3Dモデルを削除", isPresented: $isShowingDeleteAlert, presenting: deleteTargetModel) { model in
			Button("削除", role: .destructive) {
				deleteModel(model)
			}
			Button("キャンセル", role: .cancel) {
				deleteTargetModel = nil
			}
		} message: { model in
			Text("「\(model.name)」を削除します。この操作は元に戻せません。")
		}
		.onChange(of: focusedEditingModelID) { _, newValue in
			if let editingID = inlineEditingModelID, newValue != editingID {
				commitInlineEdit()
			}
		}
	}

	@ViewBuilder
	private func row(for model: ScannedModel) -> some View {
		Group {
			if inlineEditingModelID == model.id {
				editingRow(for: model)
			} else {
				Button {
					selectedModel = model
				} label: {
					normalRowContent(for: model)
						.frame(maxWidth: .infinity, alignment: .leading)
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
			}
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			Button(role: .destructive) {
				requestDelete(model)
			} label: {
				Label("削除", systemImage: "trash")
			}
		}
	}

	@ViewBuilder
	private func normalRowContent(for model: ScannedModel) -> some View {
		HStack(spacing: 16) {
			thumbnail(for: model)

			VStack(alignment: .leading, spacing: 5) {
				Text(model.name)
					.font(.headline)
					.foregroundStyle(AppColors.textPrimary)
					.onLongPressGesture {
						beginInlineEditing(model)
					}
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
		.contentShape(Rectangle())
	}

	@ViewBuilder
	private func editingRow(for model: ScannedModel) -> some View {
		HStack(spacing: 16) {
			thumbnail(for: model)

			VStack(alignment: .leading, spacing: 5) {
				TextField("モデル名", text: $inlineEditedModelName)
					.font(.headline)
					.foregroundStyle(AppColors.textPrimary)
					.textFieldStyle(.plain)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.focused($focusedEditingModelID, equals: model.id)
					.onAppear {
						focusedEditingModelID = model.id
					}
					.onSubmit {
						commitInlineEdit()
					}
					.padding(.vertical, 2)
					.padding(.horizontal, 8)
					.background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 10, style: .continuous)
							.stroke(AppColors.separator, lineWidth: 1)
					)
					.padding(.trailing, 16)

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

	private func beginInlineEditing(_ model: ScannedModel) {
		inlineEditingModelID = model.id
		inlineEditedModelName = model.name
		inlineOriginalModelName = model.name
		focusedEditingModelID = model.id
	}

	private func commitInlineEdit() {
		guard let editingID = inlineEditingModelID,
		      let model = models.first(where: { $0.id == editingID }) else {
			clearInlineEditingState()
			return
		}

		let trimmed = inlineEditedModelName.trimmingCharacters(in: .whitespacesAndNewlines)
		let nextName = trimmed.isEmpty ? inlineOriginalModelName : trimmed

		if model.name != nextName {
			model.name = nextName
			model.updatedAt = .now
			try? modelContext.save()
		}

		clearInlineEditingState()
	}

	private func requestDelete(_ model: ScannedModel) {
		commitInlineEdit()
		deleteTargetModel = model
		isShowingDeleteAlert = true
	}

	private func deleteModel(_ model: ScannedModel) {
		if selectedModel?.id == model.id {
			selectedModel = nil
		}

		if inlineEditingModelID == model.id {
			clearInlineEditingState()
		}

		if let modelPath = model.modelPath {
			try? ScannedModelStore.delete(relativePath: modelPath)
		}

		if let captureDirectoryPath = model.captureDirectoryPath {
			try? ScannedModelStore.delete(relativePath: captureDirectoryPath)
		}

		modelContext.delete(model)
		try? modelContext.save()

		deleteTargetModel = nil
		isShowingDeleteAlert = false
	}

	private func clearInlineEditingState() {
		inlineEditingModelID = nil
		inlineEditedModelName = ""
		inlineOriginalModelName = ""
		focusedEditingModelID = nil
	}

	private func sortedModels() -> [ScannedModel] {
		switch sortOption {
		case .addedDate:
			return models.sorted {
				compare($0.createdAt, $1.createdAt)
					?? compareNames($0.name, $1.name)
			}
		case .lastOpenedDate:
			return models.sorted {
				let lhs = $0.lastOpenedAt ?? .distantPast
				let rhs = $1.lastOpenedAt ?? .distantPast
				return compare(lhs, rhs) ?? compareNames($0.name, $1.name)
			}
		case .kanaOrder:
			return models.sorted {
				let lhs = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
				let rhs = $1.name.trimmingCharacters(in: .whitespacesAndNewlines)
				let comparison = lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive], range: nil, locale: Locale(identifier: "ja_JP"))
				if comparison != .orderedSame {
					return sortDirection == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
				}
				return compare($0.createdAt, $1.createdAt) ?? false
			}
		}
	}

	private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool? {
		if lhs == rhs {
			return nil
		}

		switch sortDirection {
		case .ascending:
			return lhs < rhs
		case .descending:
			return lhs > rhs
		}
	}

	private func compareNames(_ lhs: String, _ rhs: String) -> Bool {
		switch sortDirection {
		case .ascending:
			return lhs.localizedStandardCompare(rhs) == .orderedAscending
		case .descending:
			return lhs.localizedStandardCompare(rhs) == .orderedDescending
		}
	}
}

private enum ScannedModelSortOption: String, CaseIterable, Identifiable {
	case addedDate
	case lastOpenedDate
	case kanaOrder

	var id: String { rawValue }

	var title: String {
		switch self {
		case .addedDate:
			"追加日"
		case .lastOpenedDate:
			"最後に開いた日"
		case .kanaOrder:
			"50音順"
		}
	}
}

private enum ScannedModelSortDirection: String, CaseIterable, Identifiable {
	case ascending
	case descending

	var id: String { rawValue }

	var title: String {
		switch self {
		case .ascending:
			"昇順"
		case .descending:
			"降順"
		}
	}
}

extension ScannedModelsView {
	private var emptyState: some View {
		VStack(spacing: 14) {
			Image(systemName: "cube.transparent")
				.font(.system(size: 42, weight: .light))
				.foregroundStyle(AppColors.textSecondary)
			Text("まだ3Dモデルがありません")
				.font(.headline)
				.foregroundStyle(AppColors.textPrimary)
			Text("さっそく右上のカメラから\n3Dモデルをスキャンしましょう")
				.font(.subheadline)
				.foregroundStyle(AppColors.textSecondary)
				.multilineTextAlignment(.center)
		}
		.padding(28)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(AppColors.groupedBackground)
	}
}

extension ScannedModelsView {
	@ViewBuilder
	private func thumbnail(for model: ScannedModel) -> some View {
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
				.background(methodColor(for: model), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
}

private struct ScannedModelsTipPage: Identifiable, CaseIterable {
	let id = UUID()
	let title: String
	let symbolName: String
	let items: [String]

	static let allCases: [ScannedModelsTipPage] = [
		ScannedModelsTipPage(
			title: "スキャン方法",
			symbolName: "camera.viewfinder",
			items: [
				"右上のカメラから物体スキャンを始めます。",
				"アプリ内では、撮影補助から3Dモデルを作る流れを案内します。",
				"スキャンが終わったら、この一覧にモデルが追加されます。"
			]
		),
		ScannedModelsTipPage(
			title: "LiDAR対応端末",
			symbolName: "ipad.gen1",
			items: [
				"LiDAR搭載端末では、より安定したスキャンがしやすくなります。",
				"対応状況は端末や利用するスキャン方式によって変わります。",
				"うまくいかないときは、まずLiDAR対応の実機かを確認してください。\n(iPhone Proシリーズ, iPad Proシリーズが対応)"
			]
		),
		ScannedModelsTipPage(
			title: "スキャンのコツ",
			symbolName: "lightbulb",
			items: [
				"対象物のまわりをゆっくり回って、いろいろな角度から撮影します。",
				"明るく、背景がごちゃつきすぎない場所だと安定しやすいです。",
				"急がず、対象物の輪郭が見えやすい状態を保つのがコツです。"
			]
		),
		ScannedModelsTipPage(
			title: "名前を変える",
			symbolName: "pencil",
			items: [
				"モデル名は一覧の項目を長押しすると変更できます。",
				"入力したらキーボードの完了で保存されます。",
				"整理しやすい名前にしておくと、AR空間で選びやすくなります。"
			]
		)
	]
}

private struct ScannedModelsTipsOverlay: View {
	let onDismiss: () -> Void
	@State private var selectedPage = 0

	private let pages = ScannedModelsTipPage.allCases

	var body: some View {
		ZStack {
			Color.black.opacity(0.52)
				.ignoresSafeArea()
				.onTapGesture {
					onDismiss()
				}

			VStack(alignment: .leading, spacing: 18) {
				HStack(alignment: .top, spacing: 12) {
					VStack(alignment: .leading, spacing: 6) {
						Text("3Dモデルの使い方")
							.font(.system(.title2, design: .rounded).weight(.bold))
							.foregroundStyle(AppColors.textPrimary)
						Text("横にスライドして、スキャンや名前変更の流れを見られます。")
							.font(.callout)
							.foregroundStyle(AppColors.textSecondary)
					}

					Spacer(minLength: 0)

					Button(action: onDismiss) {
						Image(systemName: "xmark")
							.font(.footnote.weight(.semibold))
							.foregroundStyle(AppColors.textSecondary)
							.frame(width: 32, height: 32)
							.background(AppColors.elevatedSurface, in: Circle())
							.overlay(Circle().stroke(AppColors.separator, lineWidth: 1))
					}
					.buttonStyle(.plain)
				}

				VStack(spacing: 14) {
					TabView(selection: $selectedPage) {
						ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
							ScannedModelsTipPageCard(page: page)
								.tag(index)
								.padding(.horizontal, 1)
						}
					}
					.tabViewStyle(.page(indexDisplayMode: .never))
					.frame(height: 280)

					HStack(spacing: 8) {
						ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
							Capsule()
								.fill(index == selectedPage ? AppColors.textPrimary : AppColors.separator)
								.frame(width: index == selectedPage ? 18 : 8, height: 8)
								.animation(.snappy(duration: 0.22), value: selectedPage)
						}
					}
					.frame(maxWidth: .infinity)

					Text("スワイプで次の項目へ")
						.font(.caption.weight(.semibold))
						.foregroundStyle(AppColors.textMuted)
				}
			}
			.padding(22)
			.frame(maxWidth: 360)
			.background(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.fill(AppColors.background)
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.stroke(AppColors.separator, lineWidth: 1)
			)
			.shadow(color: Color.black.opacity(0.24), radius: 30, x: 0, y: 16)
			.padding(.horizontal, 20)
			.transition(.scale(scale: 0.96).combined(with: .opacity))
		}
	}
}

private struct ScannedModelsTipPageCard: View {
	let page: ScannedModelsTipPage

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Image(systemName: page.symbolName)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(AppColors.textPrimary)
					.frame(width: 28, height: 28)
					.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
				Text(page.title)
					.font(.headline.weight(.semibold))
					.foregroundStyle(AppColors.textPrimary)
			}

			VStack(alignment: .leading, spacing: 8) {
				ForEach(page.items, id: \.self) { item in
					HStack(alignment: .top, spacing: 8) {
						Circle()
							.fill(AppColors.textPrimary)
							.frame(width: 5, height: 5)
							.padding(.top, 6)
						Text(item)
							.font(.subheadline)
							.foregroundStyle(AppColors.textSecondary)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(16)
		.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.stroke(AppColors.separator, lineWidth: 1)
		)
	}
}

private func methodColor(for model: ScannedModel) -> Color {
	switch model.method {
	case .lidar:
		.blue
	case .photogrammetry:
		.orange
	case .objectCapture:
		.indigo
	case .trueDepth:
		.green
	}
}

struct ScannedModelPreviewView: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(\.colorScheme) private var colorScheme
	let model: ScannedModel
	@State private var previewController = ScannedModelPreviewController()
	@State private var didCommitPreviewState = false
	@State private var didMarkOpened = false

	var body: some View {
		VStack(spacing: 16) {
			ScannedModelPreviewRealityView(
				scannedModel: model,
				backgroundColor: scannedModelPreviewBackgroundColor(colorScheme: colorScheme),
				controller: previewController
			)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background(AppColors.background)
				.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 28, style: .continuous)
						.stroke(AppColors.separator, lineWidth: 1)
				)
				.padding(.horizontal, 16)
				.padding(.top, 16)

			Text(model.name)
				.font(.title2.weight(.bold))
				.foregroundStyle(AppColors.textPrimary)
				.multilineTextAlignment(.center)
			.padding(.horizontal, 20)
			.padding(.bottom, 18)
		}
		.background(AppColors.groupedBackground)
		.navigationTitle("")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			markOpenedIfNeeded()
		}
		.onDisappear {
			commitPreviewStateIfNeeded()
		}
	}

	private func markOpenedIfNeeded() {
		guard didMarkOpened == false else {
			return
		}

		model.lastOpenedAt = .now
		try? modelContext.save()
		didMarkOpened = true
	}

	private func commitPreviewStateIfNeeded() {
		guard didCommitPreviewState == false else {
			return
		}

		var didUpdate = false

		if let transform = previewController.snapshotCurrentTransform() {
			model.previewTransformSnapshot = transform
			didUpdate = true
		}

		if let snapshotImage = previewController.snapshotCurrentImage(),
		   let thumbnailData = snapshotImage.encodedThumbnailData() {
			model.thumbnailData = thumbnailData
			didUpdate = true
		}

		if didUpdate {
			model.updatedAt = .now
			try? modelContext.save()
		}

		didCommitPreviewState = true
	}
}

private func scannedModelPreviewBackgroundColor(colorScheme: ColorScheme) -> UIColor {
	switch colorScheme {
	case .dark:
		return UIColor.tertiarySystemBackground
	case .light:
		return UIColor.systemBackground
	}
}
