import ARKit
import RealityKit
import SwiftData
import SwiftUI
import _RealityKit_SwiftUI

/// LiDAR / フォトグラメトリの方式選択とスキャン実行画面です。
struct ModelScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: ScanMethod = .lidar

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("スキャン方式", selection: $selectedMethod) {
                    ForEach(ScanMethod.allCases) { method in
                        Label(method.title, systemImage: method.symbolName)
                            .tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Group {
                    switch selectedMethod {
                    case .lidar:
                        LiDARScanView()
                    case .photogrammetry:
                        PhotogrammetryScanView()
                    case .trueDepth:
                        TrueDepthAssistScanView()
                    }
                }
            }
            .background(Color(red: 0.98, green: 0.98, blue: 0.97))
            .navigationTitle("物体スキャン")
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

/// LiDAR方式の簡易スキャン保存画面です。
struct LiDARScanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var meshAnchorCount = 0
    @State private var latestSnapshot = ScannedMeshSnapshot(anchors: [])
    @State private var statusMessage = "物体の周囲をゆっくり映してください。"

    var body: some View {
        Group {
            if ARWorldTrackingConfiguration.isSupported,
               ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                ZStack(alignment: .bottom) {
                    LiDARScanCaptureView { count, snapshot in
                        meshAnchorCount += count
                        latestSnapshot = snapshot
                        statusMessage = "LiDARメッシュ検出中: \(meshAnchorCount) サンプル"
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 16)

                    controls
                }
            } else {
                unsupportedLiDARView
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(statusMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.elevatedSurface, in: Capsule())

            Button {
                saveLiDARScan()
            } label: {
                Label("LiDARスキャンを保存", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(16)
    }

    private var unsupportedLiDARView: some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder.circle")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
            Text("この端末ではLiDARメッシュを利用できません")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text("LiDAR搭載の実機でスキャンを試してください。")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveLiDARScan() {
        let id = UUID()
        do {
            let saveResult = try ScannedModelStore.createLiDARSnapshotDirectory(for: id, snapshot: latestSnapshot)
            let model = ScannedModel(
                id: id,
                name: "LiDARモデル\(Date().formatted(date: .omitted, time: .shortened))",
                method: .lidar,
                status: .captured,
                modelPath: saveResult.modelPath,
                captureDirectoryPath: saveResult.captureDirectoryPath,
                shotCount: meshAnchorCount
            )
            modelContext.insert(model)
            try modelContext.save()
            statusMessage = "LiDARスキャンを保存しました。3Dモデル一覧から確認できます。"
        } catch {
            statusMessage = "保存に失敗しました。もう一度試してください。"
        }
    }
}

/// TrueDepthで近距離の深度点群と実寸目安を保存する補助スキャンです。
struct TrueDepthAssistScanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var latestSnapshot = TrueDepthSnapshot(points: [], boundingBox: nil, capturedAt: .now)
    @State private var statusMessage = "前面カメラにフィギュアを向けてください。"

    var body: some View {
        Group {
            if TrueDepthCaptureView.isSupported {
                ZStack(alignment: .bottom) {
                    TrueDepthCaptureView { snapshot in
                        latestSnapshot = snapshot
                    } onStatusChanged: { message in
                        statusMessage = message
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 16)

                    controls
                }
            } else {
                unsupportedTrueDepthView
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(statusMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.elevatedSurface, in: Capsule())

            Button {
                saveTrueDepthScan()
            } label: {
                Label("TrueDepth補助データを保存", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .disabled(latestSnapshot.isEmpty)
        }
        .padding(16)
    }

    private var unsupportedTrueDepthView: some View {
        VStack(spacing: 12) {
            Image(systemName: "faceid")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
            Text("この端末ではTrueDepth深度を利用できません")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text("Face ID搭載端末の前面TrueDepthカメラで試してください。")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveTrueDepthScan() {
        let id = UUID()
        do {
            let saveResult = try ScannedModelStore.createTrueDepthSnapshotDirectory(for: id, snapshot: latestSnapshot)
            let model = ScannedModel(
                id: id,
                name: "TrueDepthモデル\(Date().formatted(date: .omitted, time: .shortened))",
                method: .trueDepth,
                status: .captured,
                modelPath: saveResult.modelPath,
                captureDirectoryPath: saveResult.captureDirectoryPath,
                shotCount: latestSnapshot.points.count
            )
            modelContext.insert(model)
            try modelContext.save()
            statusMessage = "TrueDepth補助データを保存しました。3Dモデル一覧から確認できます。"
        } catch {
            statusMessage = "保存に失敗しました。もう一度試してください。"
        }
    }
}

/// 通常の背面カメラで写真を集め、PhotogrammetrySessionでUSDZ生成を試す画面です。
@MainActor
struct PhotogrammetryScanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var currentModelID = UUID()
    @State private var captureDirectoryPath: String?
    @State private var captureDirectoryURL: URL?
    @State private var statusMessage = "開始すると撮影画像を集めます。"
    @State private var isProcessing = false
    @State private var shotsTaken = 0
    @State private var hasStartedCapture = false
    @State private var captureRequestToken = 0

    var body: some View {
        VStack(spacing: 12) {
            if ManualPhotogrammetryCaptureView.isSupported,
               PhotogrammetrySession.isSupported,
               let captureDirectoryURL {
                ZStack(alignment: .bottom) {
                    ManualPhotogrammetryCaptureView(
                        captureDirectoryURL: captureDirectoryURL,
                        captureRequestToken: captureRequestToken
                    ) { count in
                        shotsTaken = count
                    } onStatusChanged: { message in
                        statusMessage = message
                    }

                    Text(statusMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.elevatedSurface, in: Capsule())
                        .padding(.bottom, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                unsupportedView
            }

            HStack(spacing: 10) {
                Button {
                    startCapture()
                } label: {
                    ScanActionButton(title: hasStartedCapture ? "準備済み" : "開始", symbolName: "play.fill")
                }
                .disabled(ManualPhotogrammetryCaptureView.isSupported == false || PhotogrammetrySession.isSupported == false || hasStartedCapture)

                Button {
                    captureRequestToken += 1
                } label: {
                    ScanActionButton(title: "撮影", symbolName: "camera")
                }
                .disabled(hasStartedCapture == false || isProcessing)

                Button {
                    finishAndProcess()
                } label: {
                    ScanActionButton(title: isProcessing ? "生成中" : "生成", symbolName: "cube")
                }
                .disabled(isProcessing || hasStartedCapture == false || shotsTaken == 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var unsupportedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
            Text(unsupportedTitle)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text(unsupportedMessage)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedTitle: String {
        if ManualPhotogrammetryCaptureView.isSupported == false {
            return "この端末では背面カメラを利用できません"
        }

        if PhotogrammetrySession.isSupported == false {
            return "この端末ではUSDZ生成を利用できません"
        }

        return "フォトグラメトリを準備中です"
    }

    private var unsupportedMessage: String {
        if ManualPhotogrammetryCaptureView.isSupported == false {
            return "カメラ権限、または実機での実行状況を確認してください。"
        }

        if PhotogrammetrySession.isSupported == false {
            return "写真撮影はできても、端末内の3D生成は非対応です。画像セットをMac等で生成する方式にしてください。"
        }

        return "少し待ってからもう一度お試しください。"
    }

    private func startCapture() {
        guard ManualPhotogrammetryCaptureView.isSupported else {
            statusMessage = "この端末では背面カメラを利用できません。"
            return
        }

        guard PhotogrammetrySession.isSupported else {
            statusMessage = "この端末では端末内USDZ生成に対応していません。"
            return
        }

        guard isProcessing == false else {
            return
        }

        currentModelID = UUID()
        shotsTaken = 0
        hasStartedCapture = false
        captureRequestToken = 0

        do {
            let directoryPath = try ScannedModelStore.createCaptureDirectory(for: currentModelID)
            captureDirectoryPath = directoryPath
            guard let directoryURL = ScannedModelStore.url(forRelativePath: directoryPath) else {
                statusMessage = "保存先を作成できませんでした。"
                return
            }

            captureDirectoryURL = directoryURL
            hasStartedCapture = true
            statusMessage = "カメラ準備中です。物体を中心に入れて撮影してください。"
        } catch {
            statusMessage = "撮影開始に失敗しました。"
        }
    }

    private func finishAndProcess() {
        guard PhotogrammetrySession.isSupported else {
            statusMessage = "この端末では端末内USDZ生成に対応していません。"
            return
        }

        guard hasStartedCapture else {
            statusMessage = "先に開始ボタンを押してください。"
            return
        }

        guard shotsTaken > 0 else {
            statusMessage = "少なくとも1枚以上撮影してから生成してください。"
            return
        }

        guard let captureDirectoryPath,
              let captureURL = ScannedModelStore.url(forRelativePath: captureDirectoryPath) else {
            statusMessage = "先に撮影を開始してください。"
            return
        }

        isProcessing = true
        statusMessage = "USDZ生成を開始します。"

        Task {
            await processPhotogrammetry(inputURL: captureURL, captureDirectoryPath: captureDirectoryPath)
        }
    }

    private func processPhotogrammetry(inputURL: URL, captureDirectoryPath: String) async {
        let outputPath = ScannedModelStore.modelFileName(for: currentModelID)
        guard let outputURL = ScannedModelStore.url(forRelativePath: outputPath) else {
            statusMessage = "出力先を作成できませんでした。"
            isProcessing = false
            return
        }

        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.sampleOrdering = .sequential
            configuration.featureSensitivity = .high

            let photogrammetrySession = try PhotogrammetrySession(input: inputURL, configuration: configuration)
            try photogrammetrySession.process(requests: [.modelFile(url: outputURL, detail: .reduced)])

            for try await output in photogrammetrySession.outputs {
                switch output {
                case .requestProgress(_, let fractionComplete):
                    statusMessage = "生成中 \(Int(fractionComplete * 100))%"
                case .requestComplete(_, _):
                    savePhotogrammetryModel(outputPath: outputPath, captureDirectoryPath: captureDirectoryPath)
                    deleteCaptureImages(relativePath: captureDirectoryPath)
                    statusMessage = "USDZ生成が完了しました。"
                case .requestError(_, _):
                    saveFailedPhotogrammetryModel(captureDirectoryPath: captureDirectoryPath)
                    statusMessage = "生成に失敗しました。撮影枚数や明るさを変えて再試験してください。"
                case .processingComplete:
                    isProcessing = false
                default:
                    break
                }
            }
        } catch {
            saveFailedPhotogrammetryModel(captureDirectoryPath: captureDirectoryPath)
            statusMessage = "生成に失敗しました。"
            isProcessing = false
        }
    }

    private func savePhotogrammetryModel(outputPath: String, captureDirectoryPath: String) {
        let model = ScannedModel(
            id: currentModelID,
            name: "フォトモデル\(Date().formatted(date: .omitted, time: .shortened))",
            method: .photogrammetry,
            status: .ready,
            modelPath: outputPath,
            captureDirectoryPath: captureDirectoryPath,
            shotCount: shotsTaken
        )
        modelContext.insert(model)
        try? modelContext.save()
    }

    private func deleteCaptureImages(relativePath: String) {
        do {
            try ScannedModelStore.delete(relativePath: relativePath)
        } catch {
            statusMessage = "USDZ生成は完了しましたが、撮影写真の削除に失敗しました。"
        }
    }

    private func saveFailedPhotogrammetryModel(captureDirectoryPath: String) {
        let model = ScannedModel(
            id: currentModelID,
            name: "フォトモデル\(Date().formatted(date: .omitted, time: .shortened))",
            method: .photogrammetry,
            status: .failed,
            captureDirectoryPath: captureDirectoryPath,
            shotCount: shotsTaken
        )
        modelContext.insert(model)
        try? modelContext.save()
    }
}

struct ScanActionButton: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
