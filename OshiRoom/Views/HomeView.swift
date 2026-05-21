import SwiftData
import SwiftUI
import UIKit

/// 作成済みの棚一覧を表示するホーム画面です。
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shelf.updatedAt, order: .reverse) private var shelves: [Shelf]
    @State private var isShowingCreation = false
    @State private var selectedShelf: Shelf?
    @State private var shelfPendingDeletion: Shelf?
    @State private var deletionErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                background

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        if shelves.isEmpty {
                            EmptyShelfView()
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(shelves) { shelf in
                                    ShelfCardView(
                                        shelf: shelf,
                                        action: {
                                            selectedShelf = shelf
                                        },
                                        deleteAction: {
                                            shelfPendingDeletion = shelf
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                }

                Button {
                    isShowingCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(.black, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                }
                .padding(.trailing, 22)
                .padding(.bottom, 26)
                .accessibilityLabel("新しい棚を作成")
            }
            .navigationTitle("自分の棚一覧")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isShowingCreation) {
                ShelfCreationView { shelf in
                    isShowingCreation = false
                    selectedShelf = shelf
                }
                .presentationDetents([.large])
            }
            .navigationDestination(item: $selectedShelf) { shelf in
                ARShelfView(shelf: shelf)
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
            colors: [Color.white, Color(red: 0.96, green: 0.96, blue: 0.94)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OshiRoom")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(AppColors.textPrimary)
            Text("飾りきれない推しグッズを、ARの棚に静かに並べましょう。")
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
        }
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
        let imagePaths = shelf.items.map(\.imagePath)

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
}

/// 棚一覧のカードです。
struct ShelfCardView: View {
    let shelf: Shelf
    let action: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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

            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.74, green: 0.04, blue: 0.10))
                    .frame(width: 42, height: 42)
                    .background(Color(red: 1.0, green: 0.92, blue: 0.92), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("棚を削除")
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

#Preview {
    HomeView()
        .modelContainer(PreviewModelContainer.make())
}
