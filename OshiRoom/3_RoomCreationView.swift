import SwiftData
import SwiftUI

/// 部屋名だけを入力して、新しいAR空間を作る画面です。
struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RoomCreationViewModel()
    let onCreated: (Room) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("新しい部屋")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("まずは部屋の名前を決めましょう。棚はAR画面の中でいくつでも追加できます。")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("部屋名")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        TextField("例: ライブ記念ルーム", text: $viewModel.name)
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(16)
                            .background(AppColors.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppColors.separator, lineWidth: 1)
                            )
                    }

                    if let message = viewModel.validationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 0.74, green: 0.04, blue: 0.10))
                    }
                }
                .padding(22)
            }
            .background(AppColors.groupedBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let room = viewModel.createRoom(in: modelContext) {
                            onCreated(room)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.canSave == false)
                }
            }
        }
    }
}

#Preview {
    RoomCreationView { _ in }
        .modelContainer(PreviewModelContainer.make())
}
