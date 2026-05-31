import ARKit
import RealityKit
import SwiftData
import SwiftUI
import _RealityKit_SwiftUI

/// ObjectCaptureのみを使う物体スキャン画面です。
struct ModelScanView: View {
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ObjectCapturePhotogrammetryScanView()
				.background(AppColors.groupedBackground)
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

/// Apple公式のObjectCapture UIで写真セットを作り、PhotogrammetrySessionでUSDZ生成します。
@MainActor
struct ObjectCapturePhotogrammetryScanView: View {
	@Environment(\.modelContext) private var modelContext
	@State private var session: ObjectCaptureSession?
	@State private var currentModelID = UUID()
	@State private var imageDirectoryPath: String?
	@State private var imageDirectoryURL: URL?
	@State private var statusMessage = "開始するとObjectCaptureで撮影補助を行います。"
	@State private var isProcessing = false
	@State private var progressText = ""

	var body: some View {
		VStack(spacing: 12) {
			Group {
				if ObjectCaptureSession.isSupported,
					 PhotogrammetrySession.isSupported {
					ZStack(alignment: .bottom) {
						if let session {
							ObjectCaptureView(session: session)
								.onChange(of: session.userCompletedScanPass) { _, isCompleted in
									if isCompleted {
										statusMessage = "撮影パスが完了しました。撮影終了を押すと生成準備に進みます。"
									}
								}
								.onChange(of: session.state) { _, state in
									statusMessage = stateMessage(for: state)
								}
						} else {
							objectCaptureIntroView
						}
					}
					.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
					.padding(.horizontal, 16)
				} else {
					objectCaptureUnsupportedView
				}
			}

			Spacer(minLength: 0)

			VStack(spacing: 8) {
				if statusLabelText.isEmpty == false {
					Text(statusLabelText)
						.font(.footnote.weight(.semibold))
						.foregroundStyle(AppColors.textPrimary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 14)
						.padding(.vertical, 10)
						.background(AppColors.elevatedSurface, in: Capsule())
				}
			}
			.frame(maxWidth: .infinity)

			objectCaptureControls
				.padding(.horizontal, 16)
				.padding(.bottom, 12)
		}
	}

	private var statusLabelText: String {
		progressText.isEmpty ? statusMessage : "\(statusMessage) \(progressText)"
	}

	private var objectCaptureIntroView: some View {
		VStack(spacing: 14) {
			Image(systemName: "cube.viewfinder")
				.font(.system(size: 42, weight: .light))
				.foregroundStyle(AppColors.textSecondary)
			Text("ObjectCapture方式")
				.font(.headline)
				.foregroundStyle(AppColors.textPrimary)
			Text("Apple公式の撮影ガイドで対象物を囲み、撮影画像セットからUSDZを生成します。")
				.font(.subheadline)
				.foregroundStyle(AppColors.textSecondary)
				.multilineTextAlignment(.center)
		}
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(AppColors.groupedBackground)
	}

	private var objectCaptureUnsupportedView: some View {
		VStack(spacing: 12) {
			Image(systemName: "cube.viewfinder")
				.font(.system(size: 42, weight: .light))
				.foregroundStyle(AppColors.textSecondary)
			Text(objectCaptureUnsupportedTitle)
				.font(.headline)
				.foregroundStyle(AppColors.textPrimary)
			Text(objectCaptureUnsupportedMessage)
				.font(.subheadline)
				.foregroundStyle(AppColors.textSecondary)
				.multilineTextAlignment(.center)
		}
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var objectCaptureUnsupportedTitle: String {
		if ObjectCaptureSession.isSupported == false {
			return "この端末ではObjectCaptureを利用できません"
		}

		if PhotogrammetrySession.isSupported == false {
			return "この端末ではUSDZ生成を利用できません"
		}

		return "ObjectCaptureを準備中です"
	}

	private var objectCaptureUnsupportedMessage: String {
		if ObjectCaptureSession.isSupported == false {
			return "LiDAR搭載端末など、ObjectCapture対応の実機で試してください。"
		}

		if PhotogrammetrySession.isSupported == false {
			return "撮影補助が使えても、端末内のUSDZ生成には対応していない可能性があります。"
		}

		return "少し待ってからもう一度お試しください。"
	}

	private var objectCaptureControls: some View {
		VStack(spacing: 10) {
			Button {
				performObjectCapturePrimaryAction()
			} label: {
				ScanActionButton(title: primaryActionTitle, symbolName: primaryActionSymbol)
			}
			.disabled(primaryActionIsDisabled)
		}
		.frame(maxWidth: .infinity)
	}

	private var primaryActionTitle: String {
		if isProcessing {
			return "生成中"
		}

		guard let session else {
			return "開始"
		}

		switch session.state {
		case .initializing:
			return "開始"
		case .ready:
			return "検出"
		case .detecting:
			return "撮影開始"
		case .capturing:
			if session.userCompletedScanPass {
				return "撮影終了"
			}
			return session.canRequestImageCapture ? "追加撮影" : "撮影中"
		case .finishing:
			return "保存中"
		case .completed:
			return "生成"
		case .failed:
			return "開始"
		@unknown default:
			return "開始"
		}
	}

	private var primaryActionSymbol: String {
		if isProcessing {
			return "hourglass"
		}

		guard let session else {
			return "play.fill"
		}

		switch session.state {
		case .initializing:
			return "play.fill"
		case .ready:
			return "viewfinder"
		case .detecting:
			return "camera"
		case .capturing:
			return "camera"
		case .finishing:
			return "checkmark.circle"
		case .completed:
			return "cube"
		case .failed:
			return "play.fill"
		@unknown default:
			return "play.fill"
		}
	}

	private var primaryActionIsDisabled: Bool {
		if isProcessing {
			return true
		}

		guard let session else {
			return ObjectCaptureSession.isSupported == false || PhotogrammetrySession.isSupported == false
		}

		switch session.state {
		case .initializing:
			return true
		case .ready:
			return false
		case .detecting:
			return false
		case .capturing:
			return session.userCompletedScanPass == false && session.canRequestImageCapture == false
		case .finishing:
			return true
		case .completed:
			return false
		case .failed:
			return false
		@unknown default:
			return true
		}
	}

	private func startObjectCapture() {
		guard ObjectCaptureSession.isSupported else {
			statusMessage = "この端末ではObjectCaptureを利用できません。"
			return
		}

		guard PhotogrammetrySession.isSupported else {
			statusMessage = "この端末では端末内USDZ生成に対応していません。"
			return
		}

		currentModelID = UUID()
		progressText = ""

		do {
			let directoryPath = try ScannedModelStore.createCaptureDirectory(for: currentModelID)
			guard let directoryURL = ScannedModelStore.url(forRelativePath: directoryPath) else {
				statusMessage = "ObjectCaptureの保存先を作成できませんでした。"
				return
			}

			session?.cancel()
			imageDirectoryPath = directoryPath
			imageDirectoryURL = directoryURL

			var configuration = ObjectCaptureSession.Configuration()
			configuration.isOverCaptureEnabled = true

			let newSession = ObjectCaptureSession()
			session = newSession
			newSession.start(imagesDirectory: directoryURL, configuration: configuration)
			statusMessage = "ObjectCaptureを開始しました。対象物を枠に入れてください。"
		} catch {
			statusMessage = "ObjectCaptureの開始に失敗しました。"
		}
	}

	private func performObjectCapturePrimaryAction() {
		guard let session else {
			startObjectCapture()
			return
		}

		switch session.state {
		case .initializing:
			break
		case .ready:
			if session.startDetecting() == false {
				statusMessage = "検出を開始できませんでした。対象物を画面中央に入れてください。"
			}
		case .detecting:
			session.startCapturing()
		case .capturing:
			if session.userCompletedScanPass {
				session.finish()
			} else if session.canRequestImageCapture {
				session.requestImageCapture()
			} else {
				statusMessage = "撮影中です。少し待ってからもう一度押してください。"
			}
		case .finishing:
			break
		case .completed:
			finishObjectCaptureAndProcess()
		case .failed:
			startObjectCapture()
		default:
			break
		}
	}

	private func finishObjectCaptureAndProcess() {
		guard let imageDirectoryPath,
					let imageDirectoryURL else {
			statusMessage = "先にObjectCaptureを開始してください。"
			return
		}

		isProcessing = true
		progressText = ""
		statusMessage = "ObjectCapture画像からUSDZ生成を開始します。"

		Task {
			await processObjectCapturePhotogrammetry(
				inputURL: imageDirectoryURL,
				captureDirectoryPath: imageDirectoryPath
			)
		}
	}

	private func processObjectCapturePhotogrammetry(inputURL: URL, captureDirectoryPath: String) async {
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
					progressText = "\(Int(fractionComplete * 100))%"
				case .requestComplete(_, _):
					saveObjectCaptureModel(outputPath: outputPath, captureDirectoryPath: captureDirectoryPath)
					deleteObjectCaptureImages(relativePath: captureDirectoryPath)
					statusMessage = "ObjectCaptureモデルの生成が完了しました。"
				case .requestError(_, _):
					saveFailedObjectCaptureModel(captureDirectoryPath: captureDirectoryPath)
					statusMessage = "ObjectCaptureモデルの生成に失敗しました。"
				case .processingComplete:
					isProcessing = false
					progressText = ""
				default:
					break
				}
			}
		} catch {
			saveFailedObjectCaptureModel(captureDirectoryPath: captureDirectoryPath)
			statusMessage = "ObjectCaptureモデルの生成に失敗しました。"
			isProcessing = false
			progressText = ""
		}
	}

	private func saveObjectCaptureModel(outputPath: String, captureDirectoryPath: String) {
		let thumbnailData = ScannedModelStore.loadCaptureThumbnailData(relativePath: captureDirectoryPath)
		let model = ScannedModel(
			id: currentModelID,
			name: "ObjectCapture\(Date().formatted(date: .omitted, time: .shortened))",
			method: .objectCapture,
			status: .ready,
			modelPath: outputPath,
			captureDirectoryPath: captureDirectoryPath,
			thumbnailData: thumbnailData,
			shotCount: session?.numberOfShotsTaken ?? 0
		)
		modelContext.insert(model)
		try? modelContext.save()
	}

	private func saveFailedObjectCaptureModel(captureDirectoryPath: String) {
		let thumbnailData = ScannedModelStore.loadCaptureThumbnailData(relativePath: captureDirectoryPath)
		let model = ScannedModel(
			id: currentModelID,
			name: "ObjectCapture\(Date().formatted(date: .omitted, time: .shortened))",
			method: .objectCapture,
			status: .failed,
			captureDirectoryPath: captureDirectoryPath,
			thumbnailData: thumbnailData,
			shotCount: session?.numberOfShotsTaken ?? 0
		)
		modelContext.insert(model)
		try? modelContext.save()
	}

	private func deleteObjectCaptureImages(relativePath: String) {
		do {
			try ScannedModelStore.delete(relativePath: relativePath)
		} catch {
			statusMessage = "USDZ生成は完了しましたが、ObjectCapture画像の削除に失敗しました。"
		}
	}

	private func stateMessage(for state: ObjectCaptureSession.CaptureState) -> String {
		switch state {
		case .initializing:
			return "ObjectCaptureを初期化しています。"
		case .ready:
			return "検出できます。検出ボタンを押してください。"
		case .detecting:
			return "対象物の範囲を調整し、撮影開始を押してください。"
		case .capturing:
			if session?.userCompletedScanPass == true {
				return "撮影パスが完了しました。撮影終了を押してください。"
			}
			return "対象物の周囲をゆっくり回って撮影してください。"
		case .finishing:
			return "撮影データを保存しています。"
		case .completed:
			return "撮影データを保存しました。生成ボタンを押してください。"
		case .failed:
			return "ObjectCaptureに失敗しました。もう一度開始してください。"
		@unknown default:
			return "ObjectCaptureの状態を確認しています。"
		}
	}
}

struct ScanActionButton: View {
	let title: String
	let symbolName: String

	var body: some View {
		Label(title, systemImage: symbolName)
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(AppColors.background)
			.frame(maxWidth: .infinity)
			.frame(height: 50)
			.background(AppColors.textPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
}
