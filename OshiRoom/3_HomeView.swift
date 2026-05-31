import SwiftData
import SwiftUI
import UIKit

/// 作成済みの棚一覧を表示するホーム画面です。
struct HomeView: View {
	@Environment(\.modelContext) private var modelContext
	@Query(sort: [SortDescriptor(\Shelf.displayOrder, order: .forward), SortDescriptor(\Shelf.updatedAt, order: .reverse)]) private var shelves: [Shelf]
	@State private var isShowingCreation = false
	@State private var selectedShelf: Shelf?
	@State private var objectListShelf: Shelf?
	@State private var shelfPendingDeletion: Shelf?
	@State private var deletionErrorMessage: String?
	@State private var isShowingModelScanner = false
	@State private var isShowingScannedModels = false
	@State private var editMode: EditMode = .inactive
	@State private var isShowingSearchField = false
	@State private var searchText = ""
	@FocusState private var isSearchFieldFocused: Bool

	var body: some View {
		NavigationStack {
			ZStack(alignment: .bottomTrailing) {
				background

                List {
                    header
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))

					if isShowingSearchField && editMode == .inactive {
						searchBar
							.listRowBackground(Color.clear)
							.listRowSeparator(.hidden)
							.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
					}

					if displayShelves.isEmpty {
						if activeSearchQuery.isEmpty {
							EmptyShelfView()
								.listRowBackground(Color.clear)
								.listRowSeparator(.hidden)
								.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
						} else {
							EmptySearchResultView(query: activeSearchQuery)
								.listRowBackground(Color.clear)
								.listRowSeparator(.hidden)
								.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
						}
					} else {
						ForEach(displayShelves) { shelf in
							ShelfCardView(
								shelf: shelf,
								action: {
									selectedShelf = shelf
								},
								objectListAction: {
									objectListShelf = shelf
								}
							)
							.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 14, trailing: 20))
							.listRowBackground(Color.clear)
							.listRowSeparator(.hidden)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button(role: .destructive) {
									shelfPendingDeletion = shelf
								} label: {
									Label("削除", systemImage: "trash")
								}
							}
						}
						.onMove(perform: moveShelves)
					}
				}
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
				.background(background)
				.environment(\.editMode, $editMode)

				Button {
					isShowingCreation = true
				} label: {
					Image(systemName: "plus")
						.font(.title2.weight(.semibold))
						.foregroundStyle(AppColors.background)
						.frame(width: 60, height: 60)
						.background(AppColors.textPrimary, in: Circle())
						.shadow(color: .black.opacity(0.18), radius: 18, y: 10)
				}
				.padding(.trailing, 22)
				.padding(.bottom, 26)
				.accessibilityLabel("新しい棚を作成")
			}
			.navigationTitle("My OshiRoom")
			.navigationBarTitleDisplayMode(.large)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					HStack(spacing: 6) {
						Button {
							toggleReorderMode()
						} label: {
							Image(systemName: editMode == .active ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
						}
						.accessibilityLabel("棚の並び替え")

						Button {
							toggleSearchField()
						} label: {
							Image(systemName: isShowingSearchField ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
						}
						.accessibilityLabel("検索")
					}
				}

				ToolbarItem(placement: .topBarTrailing) {
					Button {
						isShowingScannedModels = true
					} label: {
						Label("3Dモデル", systemImage: "cube")
					}
					.accessibilityLabel("3Dモデル一覧")
				}
			}
			.sheet(isPresented: $isShowingCreation) {
				ShelfCreationView { shelf in
					isShowingCreation = false
					selectedShelf = shelf
				}
				.presentationDetents([.large])
			}
			.sheet(isPresented: $isShowingModelScanner) {
				ModelScanView()
					.presentationDetents([.large])
			}
			.navigationDestination(item: $selectedShelf) { shelf in
				ARShelfView(shelf: shelf)
			}
			.navigationDestination(isPresented: $isShowingScannedModels) {
				ScannedModelsView()
			}
			.sheet(item: $objectListShelf) { shelf in
				ShelfObjectListView(shelf: shelf)
					.presentationDetents([.medium, .large])
			}
			.confirmationDialog("棚を削除しますか？", isPresented: isShowingDeletionConfirmation, titleVisibility: .visible) {
				Button("削除", role: .destructive) {
					if let shelfPendingDeletion {
						deleteShelf(shelfPendingDeletion)
					}
				}
				Button("キャンセル", role: .cancel) {}
			} message: {
				Text("「\(shelfPendingDeletion?.name ?? "この棚")」と棚に追加したグッズを削除します。この操作は取り消せません。")
			}
			.alert("棚を削除できませんでした", isPresented: isShowingDeletionError) {
				Button("OK", role: .cancel) {
					deletionErrorMessage = nil
				}
			} message: {
				Text(deletionErrorMessage ?? "時間をおいてもう一度お試しください。")
			}
		}
	}

	private var background: some View {
		LinearGradient(
			colors: [AppColors.background, AppColors.groupedBackground],
			startPoint: .top,
			endPoint: .bottom
		)
		.ignoresSafeArea()
	}

	private var displayShelves: [Shelf] {
		if editMode == .active {
			return shelves
		}

		guard activeSearchQuery.isEmpty == false else {
			return shelves
		}

		return shelves.filter { shelf in
			shelfMatchesQuery(shelf, query: activeSearchQuery)
		}
	}

	private var activeSearchQuery: String {
		searchText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 8) {
			//            Text("OshiRoom")
			//                .font(.system(.title, design: .rounded).weight(.bold))
			//                .foregroundStyle(AppColors.textPrimary)
			Text("飾りきれないあなたの推しグッズを\nARの棚に静かに並べましょう。")
				.font(.callout)
				.foregroundStyle(AppColors.textSecondary)
		}
	}

	private var searchBar: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(AppColors.textMuted)

			TextField("棚名・オブジェクト名を検索", text: $searchText)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.focused($isSearchFieldFocused)

			if searchText.isEmpty == false {
				Button {
					searchText = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.font(.subheadline)
						.foregroundStyle(AppColors.textMuted)
				}
				.accessibilityLabel("検索文字を消去")
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.background(AppColors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.stroke(AppColors.separator, lineWidth: 1)
		)
	}

	private var isShowingDeletionError: Binding<Bool> {
		Binding(
			get: { deletionErrorMessage != nil },
			set: { isShowing in
				if isShowing == false {
					deletionErrorMessage = nil
				}
			}
		)
	}

	private var isShowingDeletionConfirmation: Binding<Bool> {
		Binding(
			get: { shelfPendingDeletion != nil },
			set: { isShowing in
				if isShowing == false {
					shelfPendingDeletion = nil
				}
			}
		)
	}

	private func deleteShelf(_ shelf: Shelf) {
		let imagePaths = shelf.items
			.filter { $0.contentType == .image && $0.imagePath.isEmpty == false }
			.map(\.imagePath)

		if selectedShelf?.id == shelf.id {
			selectedShelf = nil
		}

		modelContext.delete(shelf)

		do {
			try modelContext.save()
			imagePaths.forEach { ImageStore.delete(path: $0) }
		} catch {
			deletionErrorMessage = "保存データの削除中に問題が起きました。"
		}
	}

	private func shelfMatchesQuery(_ shelf: Shelf, query: String) -> Bool {
		if shelf.name.localizedStandardContains(query) {
			return true
		}

		return shelf.items.enumerated().contains { pair in
			let index = pair.offset
			let item = pair.element
			let itemName = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
			let fallbackName = "オブジェクト\(index + 1)"
			let candidateNames = [itemName, fallbackName].compactMap { $0 }

			return candidateNames.contains { $0.localizedStandardContains(query) }
		}
	}

	private func toggleSearchField() {
		if editMode == .active {
			editMode = .inactive
			isShowingSearchField = true
			isSearchFieldFocused = true
			return
		}

		isShowingSearchField.toggle()

		if isShowingSearchField {
			isSearchFieldFocused = true
			return
		}

		searchText = ""
		isSearchFieldFocused = false
	}

	private func toggleReorderMode() {
		if editMode == .active {
			editMode = .inactive
			return
		}

		isShowingSearchField = false
		isSearchFieldFocused = false
		editMode = .active
	}

	private func moveShelves(from source: IndexSet, to destination: Int) {
		var updatedShelves = shelves
		updatedShelves.move(fromOffsets: source, toOffset: destination)

		for (index, shelf) in updatedShelves.enumerated() {
			shelf.displayOrder = index
		}

		try? modelContext.save()
	}
}

/// 棚一覧のカードです。
struct ShelfCardView: View {
	let shelf: Shelf
	let action: () -> Void
	let objectListAction: () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Button(action: action) {
				HStack(spacing: 16) {
					thumbnail

					VStack(alignment: .leading, spacing: 8) {
						Text(shelf.name)
							.font(.headline)
							.foregroundStyle(AppColors.textPrimary)
						Text(shelf.template.title)
							.font(.subheadline)
							.foregroundStyle(AppColors.textSecondary)
						Text("最終更新日: \(shelf.updatedAt.formatted(date: .abbreviated, time: .shortened))")
							.font(.caption)
							.foregroundStyle(AppColors.textMuted)
					}

					Spacer()

					Image(systemName: "chevron.right")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(AppColors.textMuted)
				}
			}
			.buttonStyle(.plain)

			Button(action: objectListAction) {
				HStack(spacing: 8) {
					Image(systemName: "rectangle.stack")
						.font(.caption.weight(.semibold))
					Text("追加済みオブジェクト一覧")
						.font(.caption.weight(.semibold))
					Spacer()
					Text("\(shelf.items.count)")
						.font(.caption.weight(.bold))
						.foregroundStyle(AppColors.textPrimary)
				}
				.foregroundStyle(AppColors.textSecondary)
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.background(AppColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.stroke(AppColors.separator, lineWidth: 1)
				)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("追加済みオブジェクト一覧を開く")
		}
		.padding(16)
		.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 26, style: .continuous)
				.stroke(AppColors.separator, lineWidth: 1)
		)
	}

	@ViewBuilder
	private var thumbnail: some View {
		if let data = shelf.thumbnailData, let image = UIImage(data: data) {
			Image(uiImage: image)
				.resizable()
				.scaledToFill()
				.frame(width: 78, height: 78)
				.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		} else {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(shelf.template.tint.opacity(0.16))
				.frame(width: 78, height: 78)
				.overlay {
					Image(systemName: shelf.template.symbolName)
						.font(.title2)
						.foregroundStyle(shelf.template.tint)
				}
		}
	}
}

/// 棚がまだないときの案内です。
struct EmptyShelfView: View {
	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "square.grid.2x2")
				.font(.system(size: 42, weight: .light))
				.foregroundStyle(AppColors.textSecondary)
				.frame(width: 88, height: 88)
				.background(AppColors.elevatedSurface, in: Circle())

			VStack(spacing: 6) {
				Text("最初の棚を作りましょう")
					.font(.headline)
					.foregroundStyle(AppColors.textPrimary)
				Text("右下の＋から棚を作成して、AR空間に配置できます。")
					.font(.subheadline)
					.foregroundStyle(AppColors.textSecondary)
					.multilineTextAlignment(.center)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 52)
		.padding(.horizontal, 24)
		.background(AppColors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 30, style: .continuous)
				.stroke(AppColors.separator, lineWidth: 1)
		)
	}
}

/// 検索に一致する棚がなかったときの案内です。
struct EmptySearchResultView: View {
	let query: String

	var body: some View {
		VStack(spacing: 14) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 38, weight: .light))
				.foregroundStyle(AppColors.textSecondary)
				.frame(width: 88, height: 88)
				.background(AppColors.elevatedSurface, in: Circle())

			VStack(spacing: 6) {
				Text("該当する棚が見つかりませんでした")
					.font(.headline)
					.foregroundStyle(AppColors.textPrimary)
				Text("「\(query)」に一致する棚名やオブジェクト名はありません。")
					.font(.subheadline)
					.foregroundStyle(AppColors.textSecondary)
					.multilineTextAlignment(.center)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 52)
		.padding(.horizontal, 24)
		.background(AppColors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 30, style: .continuous)
				.stroke(AppColors.separator, lineWidth: 1)
		)
	}
}

/// 棚に追加済みのグッズを一覧し、名前を編集する画面です。
struct ShelfObjectListView: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var modelContext
	@Query(sort: \ScannedModel.updatedAt, order: .reverse) private var scannedModels: [ScannedModel]
	let shelf: Shelf

	private var sortedItems: [PlacedItem] {
		shelf.items.sorted { $0.slotIndex < $1.slotIndex }
	}

	var body: some View {
		NavigationStack {
			Group {
				if sortedItems.isEmpty {
					emptyState
				} else {
					List {
						ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
							ShelfObjectRow(
								item: item,
								fallbackName: "オブジェクト\(index + 1)",
								modelThumbnailData: modelThumbnailData(for: item.modelPath)
							)
							.listRowSeparator(.hidden)
							.listRowBackground(Color.clear)
						}
					}
					.listStyle(.plain)
					.scrollContentBackground(.hidden)
					.background(AppColors.groupedBackground)
				}
			}
			.navigationTitle("追加済みオブジェクト一覧")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("閉じる") {
						saveChanges()
						dismiss()
					}
				}
			}
			.onDisappear {
				saveChanges()
			}
		}
	}

	private var emptyState: some View {
		VStack(spacing: 14) {
			Image(systemName: "rectangle.stack.badge.plus")
				.font(.system(size: 38, weight: .light))
				.foregroundStyle(AppColors.textSecondary)
			Text("まだグッズがありません")
				.font(.headline)
				.foregroundStyle(AppColors.textPrimary)
			Text("AR画面の「グッズ追加」から写真を追加すると、ここに一覧表示されます。")
				.font(.subheadline)
				.foregroundStyle(AppColors.textSecondary)
				.multilineTextAlignment(.center)
		}
		.padding(28)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(AppColors.groupedBackground)
	}

	private func saveChanges() {
		shelf.updatedAt = .now
		try? modelContext.save()
	}

	private func modelThumbnailData(for modelPath: String?) -> Data? {
		guard let modelPath else {
			return nil
		}

		return scannedModels.first { $0.modelPath == modelPath }?.previewThumbnailData
	}
}

/// グッズ一覧の1行です。
struct ShelfObjectRow: View {
	@Bindable var item: PlacedItem
	let fallbackName: String
	let modelThumbnailData: Data?

	var body: some View {
		HStack(spacing: 12) {
			thumbnail

			VStack(alignment: .leading, spacing: 8) {
				Text("グッズ名")
					.font(.caption.weight(.semibold))
					.foregroundStyle(AppColors.textMuted)

				TextField(fallbackName, text: displayNameBinding)
					.font(.body.weight(.semibold))
					.foregroundStyle(AppColors.textPrimary)
					.textFieldStyle(.plain)
					.padding(.horizontal, 12)
					.padding(.vertical, 10)
					.background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 14, style: .continuous)
							.stroke(AppColors.separator, lineWidth: 1)
					)
			}
		}
		.padding(12)
		.background(AppColors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(AppColors.separator, lineWidth: 1)
		)
		.padding(.vertical, 4)
	}

	private var displayNameBinding: Binding<String> {
		Binding(
			get: { item.displayName?.isEmpty == false ? item.displayName ?? fallbackName : fallbackName },
			set: { newValue in
				let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
				item.displayName = trimmedValue.isEmpty ? nil : newValue
			}
		)
	}

	@ViewBuilder
	private var thumbnail: some View {
		if item.contentType == .model3D {
			if let modelThumbnailData,
				 let image = UIImage(data: modelThumbnailData) {
				Image(uiImage: image)
					.resizable()
					.scaledToFill()
					.frame(width: 62, height: 62)
					.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
			} else {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(Color.green.opacity(0.14))
					.frame(width: 62, height: 62)
					.overlay {
						Image(systemName: "cube")
							.foregroundStyle(Color.green)
					}
			}
		} else if let image = ImageStore.load(path: item.imagePath) {
			Image(uiImage: image)
				.resizable()
				.scaledToFill()
				.frame(width: 62, height: 62)
				.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		} else {
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(AppColors.elevatedSurface)
				.frame(width: 62, height: 62)
				.overlay {
					Image(systemName: "photo")
						.foregroundStyle(AppColors.textMuted)
				}
		}
	}
}

#Preview {
	HomeView()
		.modelContainer(PreviewModelContainer.make())
}
