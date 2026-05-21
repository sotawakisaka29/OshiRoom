import PhotosUI
import SwiftUI
import UIKit

/// 写真を選択し、背景除去済みグッズを作成する画面です。
struct AddGoodsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddGoodsViewModel()
    @State private var isShowingCamera = false
    let onCreated: (UIImage, String) -> Void

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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                }

                if viewModel.isProcessing {
                    ProgressView("作成中")
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding(22)
            .background(Color(red: 0.98, green: 0.98, blue: 0.97).ignoresSafeArea())
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
        }
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
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

#Preview {
    AddGoodsView { _, _ in }
}
