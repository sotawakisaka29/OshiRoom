import SwiftData
import SwiftUI

/// スキャン済み3Dモデルの一覧画面です。
struct ScannedModelsView: View {
    @Query(sort: \ScannedModel.updatedAt, order: .reverse) private var models: [ScannedModel]
    @State private var selectedModel: ScannedModel?

    var body: some View {
        NavigationStack {
            Group {
                if models.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(models) { model in
                            Button {
                                selectedModel = model
                            } label: {
                                ScannedModelRow(model: model)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(red: 0.98, green: 0.98, blue: 0.97))
                }
            }
            .navigationTitle("3Dモデル")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedModel) { model in
                ScannedModelPreviewView(model: model)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
            Text("まだ3Dモデルがありません")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text("トップ右上のカメラからLiDARまたはフォトグラメトリの試験スキャンを開始できます。")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.98, green: 0.98, blue: 0.97))
    }
}

struct ScannedModelRow: View {
    let model: ScannedModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.method.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(methodColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(model.name)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(model.method.title) / \(model.status.title)")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Text("撮影数: \(model.shotCount) ・ \(model.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(AppColors.textMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textMuted)
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColors.separator, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var methodColor: Color {
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
}

struct ScannedModelPreviewView: View {
    let model: ScannedModel

    var body: some View {
        VStack(spacing: 16) {
            ScannedModelPreviewRealityView(scannedModel: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppColors.separator, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text(model.method.title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(model.modelPath == nil ? "生成済みUSDZがないため試験用プレースホルダーを表示しています。" : "白背景のバーチャル空間で生成モデルを表示しています。")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.97))
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
