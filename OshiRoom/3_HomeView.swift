import SwiftData
import SwiftUI
import UIKit

/// 作成済みの部屋一覧を表示するホーム画面です。
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Room.displayOrder, order: .forward), SortDescriptor(\Room.updatedAt, order: .reverse)]) private var rooms: [Room]
    @State private var isShowingCreation = false
    @State private var selectedRoom: Room?
    @State private var isShowingRoomLoading = false
    @State private var loadingRoomName = ""
    @State private var roomEntryLoadingStartedAt: Date?
    @State private var roomEntryLoadingTask: Task<Void, Never>?
    @State private var objectListRoom: Room?
    @State private var roomPendingRename: Room?
    @State private var renameErrorMessage: String?
    @State private var roomPendingDeletion: Room?
    @State private var deletionErrorMessage: String?
    @State private var isShowingScannedModels = false
    @State private var isShowingSearchField = false
    @State private var searchText = ""
    @State private var draggedRoomID: UUID?
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

                    if isShowingSearchField {
                        searchBar
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                    }

                    if displayRooms.isEmpty {
                        if activeSearchQuery.isEmpty {
                            EmptyRoomView()
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
                        ForEach(displayRooms) { room in
                            RoomCardView(
                                room: room,
                                action: {
                                    beginRoomEntry(room)
                                },
                                renameAction: {
                                    roomPendingRename = room
                                },
                                objectListAction: {
                                    objectListRoom = room
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 14, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    roomPendingDeletion = room
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .draggable(activeSearchQuery.isEmpty ? room.id.uuidString : "")
                            .dropDestination(for: String.self) { items, _ in
                                guard activeSearchQuery.isEmpty,
                                      let sourceIDString = items.first,
                                      let sourceID = UUID(uuidString: sourceIDString) else {
                                    return false
                                }
                                reorderRooms(from: sourceID, to: room.id)
                                return true
                            } isTargeted: { isTargeted in
                                if isTargeted {
                                    draggedRoomID = room.id
                                } else if draggedRoomID == room.id {
                                    draggedRoomID = nil
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(background)

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
                .accessibilityLabel("新しい部屋を作成")

                if isShowingRoomLoading {
                    RoomEntryLoadingOverlay(roomName: loadingRoomName)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationTitle("My Oshi Room")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleSearchField()
                    } label: {
                        Image(systemName: isShowingSearchField ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                    }
                    .accessibilityLabel("検索")
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
                RoomCreationView { room in
                    isShowingCreation = false
                    beginRoomEntry(room)
                }
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(item: $selectedRoom) { room in
                ARShelfView(room: room) {
                    finishRoomEntryLoading()
                }
            }
            .navigationDestination(isPresented: $isShowingScannedModels) {
                ScannedModelsView()
            }
            .sheet(item: $objectListRoom) { room in
                RoomObjectListView(room: room)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $roomPendingRename) { room in
                RoomRenameView(room: room) { updatedName in
                    if renameRoom(room, to: updatedName) {
                        roomPendingRename = nil
                        return true
                    }

                    return false
                } onCancel: {
                    roomPendingRename = nil
                }
                .presentationDetents([.medium])
            }
            .alert("部屋名を変更できませんでした", isPresented: isShowingRenameError) {
                Button("OK", role: .cancel) {
                    renameErrorMessage = nil
                }
            } message: {
                Text(renameErrorMessage ?? "時間をおいてもう一度お試しください。")
            }
            .confirmationDialog("部屋を削除しますか？", isPresented: isShowingDeletionConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let roomPendingDeletion {
                        deleteRoom(roomPendingDeletion)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("「\(roomPendingDeletion?.name ?? "この部屋")」にある棚とグッズを削除します。この操作は取り消せません。")
            }
            .alert("部屋を削除できませんでした", isPresented: isShowingDeletionError) {
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

    private var displayRooms: [Room] {
        guard activeSearchQuery.isEmpty == false else {
            return rooms
        }

        return rooms.filter { room in
            roomMatchesQuery(room, query: activeSearchQuery)
        }
    }

    private var activeSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginRoomEntry(_ room: Room) {
        loadingRoomName = room.name
        roomEntryLoadingStartedAt = .now
        isShowingRoomLoading = true
        DispatchQueue.main.async {
            selectedRoom = room
        }
    }

    private func finishRoomEntryLoading() {
        roomEntryLoadingTask?.cancel()

        roomEntryLoadingTask = Task {
            let minimumDisplayDuration: TimeInterval = 1.0
            let elapsed = Date().timeIntervalSince(roomEntryLoadingStartedAt ?? .now)
            let remaining = max(0, minimumDisplayDuration - elapsed)

            if remaining > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                } catch {
                    return
                }
            }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowingRoomLoading = false
                }
                roomEntryLoadingStartedAt = nil
                roomEntryLoadingTask = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            TextField("部屋名・オブジェクト名を検索", text: $searchText)
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

    private var isShowingRenameError: Binding<Bool> {
        Binding(
            get: { renameErrorMessage != nil },
            set: { isShowing in
                if isShowing == false {
                    renameErrorMessage = nil
                }
            }
        )
    }

    private var isShowingDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { roomPendingDeletion != nil },
            set: { isShowing in
                if isShowing == false {
                    roomPendingDeletion = nil
                }
            }
        )
    }

    private func deleteRoom(_ room: Room) {
        let imagePaths = room.shelves
            .flatMap(\.items)
            .filter { $0.contentType == .image && $0.imagePath.isEmpty == false }
            .map(\.imagePath)

        if selectedRoom?.id == room.id {
            selectedRoom = nil
        }

        modelContext.delete(room)

        do {
            try modelContext.save()
            imagePaths.forEach { ImageStore.delete(path: $0) }
        } catch {
            deletionErrorMessage = "保存データの削除中に問題が起きました。"
        }
    }

    private func renameRoom(_ room: Room, to newName: String) -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            renameErrorMessage = "部屋名を空欄にはできません。"
            return false
        }

        room.name = trimmedName
        room.updatedAt = .now

        do {
            try modelContext.save()
            return true
        } catch {
            renameErrorMessage = "部屋名の保存中に問題が起きました。"
            return false
        }
    }

    private func roomMatchesQuery(_ room: Room, query: String) -> Bool {
        if room.name.localizedStandardContains(query) {
            return true
        }

        return room.shelves.contains { shelf in
            shelf.items.enumerated().contains { pair in
                let fallbackName = "オブジェクト\(pair.offset + 1)"
                let itemName = pair.element.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                return [itemName, fallbackName]
                    .compactMap { $0 }
                    .contains { $0.localizedStandardContains(query) }
            }
        }
    }

    private func toggleSearchField() {
        isShowingSearchField.toggle()

        if isShowingSearchField {
            isSearchFieldFocused = true
            return
        }

        searchText = ""
        isSearchFieldFocused = false
    }

    private func reorderRooms(from sourceID: UUID, to targetID: UUID) {
        guard sourceID != targetID else {
            return
        }

        var updatedRooms = rooms
        guard let sourceIndex = updatedRooms.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = updatedRooms.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movedRoom = updatedRooms.remove(at: sourceIndex)
        updatedRooms.insert(movedRoom, at: targetIndex)

        for (index, room) in updatedRooms.enumerated() {
            room.displayOrder = index
        }

        try? modelContext.save()
    }
}

/// 部屋一覧のカードです。
struct RoomCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let room: Room
    let action: () -> Void
    let renameAction: () -> Void
    let objectListAction: () -> Void

    private var leadShelf: Shelf? {
        room.shelves.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    private var objectCount: Int {
        room.shelves.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                thumbnail

                VStack(alignment: .leading, spacing: 8) {
                    Button(action: renameAction) {
                        HStack(spacing: 6) {
                            Text(room.name)
                                .font(.headline)
                                .foregroundStyle(AppColors.textPrimary)

                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("部屋名を変更")

                    Text("\(room.shelves.count)台の棚")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("最終更新日: \(room.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(AppColors.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.textMuted)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)

            HStack(spacing: 10) {
                Button(action: objectListAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption.weight(.semibold))
                        Text("追加済みオブジェクト一覧")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(objectCount)")
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
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var cardBackground: Color {
        switch colorScheme {
        case .light:
            return Color(uiColor: .systemGray6)
        @unknown default:
            return AppColors.elevatedSurface
        }
    }

    private var cardBorder: Color {
        switch colorScheme {
        case .light:
            return AppColors.separator.opacity(0.55)
        @unknown default:
            return AppColors.separator
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = leadShelf?.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if let leadShelf {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(leadShelf.template.tint.opacity(0.16))
                .frame(width: 78, height: 78)
                .overlay {
                    Image(systemName: leadShelf.template.symbolName)
                        .font(.title2)
                        .foregroundStyle(leadShelf.template.tint)
                }
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.elevatedSurface)
                .frame(width: 78, height: 78)
                .overlay {
                    Image(systemName: "house")
                        .font(.title2)
                        .foregroundStyle(AppColors.textMuted)
                }
        }
    }
}

/// ホーム画面から部屋名を変更するための編集画面です。
struct RoomRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    let room: Room
    let onSave: (String) -> Bool
    let onCancel: () -> Void

    init(room: Room, onSave: @escaping (String) -> Bool, onCancel: @escaping () -> Void) {
        self.room = room
        self.onSave = onSave
        self.onCancel = onCancel
        _draftName = State(initialValue: room.name)
    }

    private var canSave: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("部屋名を変更")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("あとから分かりやすい名前に変えられます。")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("部屋名")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        TextField("例: ライブ記念ルーム", text: $draftName)
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(16)
                            .background(AppColors.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppColors.separator, lineWidth: 1)
                            )
                    }
                }
                .padding(22)
            }
            .background(AppColors.groupedBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard canSave else {
                            return
                        }

                        if onSave(draftName) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(canSave == false)
                }
            }
        }
    }
}

/// 部屋がまだないときの案内です。
struct EmptyRoomView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "house")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 88, height: 88)
                .background(AppColors.elevatedSurface, in: Circle())

            VStack(spacing: 6) {
                Text("最初の部屋を作りましょう")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("右下の＋から部屋を作成して、AR画面の中で棚を追加できます。")
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

/// 検索に一致する部屋がなかったときの案内です。
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
                Text("該当する部屋が見つかりませんでした")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("「\(query)」に一致する部屋名やオブジェクト名はありません。")
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

private struct RoomObjectListEntry: Identifiable {
    let shelf: Shelf
    let item: PlacedItem
    let fallbackName: String

    var id: UUID { item.id }
}

/// 部屋内のグッズを一覧し、名前を編集する画面です。
struct RoomObjectListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScannedModel.updatedAt, order: .reverse) private var scannedModels: [ScannedModel]
    let room: Room
    @State private var isShowingEmptyNameAlert = false
    @State private var lastFocusedItemID: UUID?
    @State private var itemIDToRefocusAfterAlert: UUID?
    @FocusState private var focusedItemID: UUID?

    private var sortedEntries: [RoomObjectListEntry] {
        room.shelves
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .flatMap { shelf in
                shelf.items
                    .sorted { $0.slotIndex < $1.slotIndex }
                    .enumerated()
                    .map { index, item in
                        RoomObjectListEntry(
                            shelf: shelf,
                            item: item,
                            fallbackName: "オブジェクト\(index + 1)"
                        )
                    }
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            RoomObjectRow(
                                shelfName: entry.shelf.name,
                                item: entry.item,
                                fallbackName: entry.fallbackName,
                                modelThumbnailData: modelThumbnailData(for: entry.item.modelPath),
                                focusedItemID: $focusedItemID
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
                        if saveChanges() {
                            dismiss()
                        }
                    }
                }
            }
            .onDisappear {
                _ = saveChanges()
            }
            .onChange(of: focusedItemID) { _, newValue in
                defer { lastFocusedItemID = newValue }

                guard newValue == nil,
                      let lastFocusedItemID,
                      let item = item(for: lastFocusedItemID),
                      (item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
                    return
                }

                itemIDToRefocusAfterAlert = lastFocusedItemID
                isShowingEmptyNameAlert = true
            }
            .alert("オブジェクト名を入力してください", isPresented: $isShowingEmptyNameAlert) {
                Button("OK", role: .cancel) {
                    let itemID = itemIDToRefocusAfterAlert
                    DispatchQueue.main.async {
                        focusedItemID = itemID
                    }
                }
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

    private func saveChanges() -> Bool {
        guard hasUnfilledObjectName == false else {
            isShowingEmptyNameAlert = true
            return false
        }

        room.updatedAt = .now
        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    private var hasUnfilledObjectName: Bool {
        sortedEntries.contains { entry in
            entry.item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    private func item(for id: UUID) -> PlacedItem? {
        room.shelves.flatMap(\.items).first { $0.id == id }
    }

    private func modelThumbnailData(for modelPath: String?) -> Data? {
        guard let modelPath else {
            return nil
        }

        return scannedModels.first { $0.modelPath == modelPath }?.previewThumbnailData
    }
}

/// グッズ一覧の1行です。
struct RoomObjectRow: View {
    let shelfName: String
    @Bindable var item: PlacedItem
    let fallbackName: String
    let modelThumbnailData: Data?
    let focusedItemID: FocusState<UUID?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 8) {
                Text(shelfName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textMuted)

                TextField("", text: displayNameBinding, prompt: Text(fallbackName))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .textFieldStyle(.plain)
                    .focused(focusedItemID, equals: item.id)
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
            get: { item.displayName ?? "" },
            set: { newValue in
                let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                item.displayName = trimmedValue.isEmpty ? nil : trimmedValue
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
