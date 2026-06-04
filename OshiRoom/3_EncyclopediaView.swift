import CryptoKit
import Foundation
import Observation
import RealityKit
import SwiftData
import SwiftUI
import UIKit

/// 全棚に登録されたグッズを重複なしで一覧する図鑑画面です。
struct EncyclopediaView: View {
    @Query(sort: \PlacedItem.createdAt, order: .reverse) private var items: [PlacedItem]
    @Query(sort: \ScannedModel.updatedAt, order: .reverse) private var scannedModels: [ScannedModel]
    @Namespace private var heroNamespace
    @State private var selectedSignature: String?

    private var catalog: EncyclopediaCatalog {
        EncyclopediaCatalog(items: items, scannedModels: scannedModels)
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4, alignment: .top),
        count: 3
    )

    var body: some View {
        let displayCatalog = catalog
        let selectedEntry = selectedSignature.flatMap { signature in
            displayCatalog.entries.first { $0.signature == signature }
        }
        let selectedScannedModel: ScannedModel? = {
            guard let entry = selectedEntry,
                  let modelPath = entry.modelPath else {
                return nil
            }

            return scannedModels.first { $0.modelPath == modelPath }
        }()

        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(catalog: displayCatalog)

                        if displayCatalog.entries.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(displayCatalog.entries) { entry in
                                    EncyclopediaGridCard(
                                        entry: entry,
                                        namespace: heroNamespace
                                    ) {
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                            selectedSignature = entry.signature
                                        }
                                    }
                                    .opacity(selectedEntry?.signature == entry.signature ? 0 : 1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                .background(AppColors.groupedBackground.ignoresSafeArea())
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("図鑑")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .allowsHitTesting(selectedEntry == nil)
            }

            if let selectedEntry {
                EncyclopediaDetailOverlay(
                    entry: selectedEntry,
                    scannedModel: selectedScannedModel,
                    namespace: heroNamespace,
                    onClose: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            selectedSignature = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private func header(catalog: EncyclopediaCatalog) -> some View {
        HStack(spacing: 8) {
            Label("\(catalog.entries.count)件", systemImage: "square.grid.2x2.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppColors.textMuted)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.separator, lineWidth: 1)
        )
        .padding(.top, 8)
    }
}

private struct EncyclopediaCatalog {
    let entries: [EncyclopediaEntry]
    let duplicateCount: Int

    init(items: [PlacedItem], scannedModels: [ScannedModel]) {
        let thumbnailMap = scannedModels.reduce(into: [String: Data]()) { result, model in
            guard let modelPath = model.modelPath,
                  let thumbnailData = model.previewThumbnailData else {
                return
            }

            result[modelPath] = thumbnailData
        }

        var seenSignatures = Set<String>()
        var entries: [EncyclopediaEntry] = []

        for item in items {
            let entry = EncyclopediaEntry(item: item, scannedModelThumbnailMap: thumbnailMap)
            guard seenSignatures.insert(entry.signature).inserted else {
                continue
            }
            entries.append(entry)
        }

        self.entries = entries
        self.duplicateCount = max(items.count - entries.count, 0)
    }
}

private struct EncyclopediaGridCard: View {
    let entry: EncyclopediaEntry
    let namespace: Namespace.ID
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            preview
                .padding(2)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.separator, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(previewBackgroundStyle)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(
                id: entry.signature,
                in: namespace,
                properties: .frame,
                anchor: .center
            )
            .overlay {
                if let image = entry.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                        .clipped()
                } else {
                    Image(systemName: entry.previewSymbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(entry.previewSymbolTint)
                }
            }
            .clipped()
    }

    private var previewBackgroundStyle: AnyShapeStyle {
        encyclopediaPreviewBackground(for: entry.contentType, colorScheme: colorScheme)
    }
}

private struct EncyclopediaDetailOverlay: View {
    let entry: EncyclopediaEntry
    let scannedModel: ScannedModel?
    let namespace: Namespace.ID
    let onClose: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var modelPreviewController = EncyclopediaModelPreviewController()
    @State private var didMarkOpened = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppColors.background
                    .ignoresSafeArea()
                    .onTapGesture {
                        commitThumbnailAndClose()
                    }

                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button(action: commitThumbnailAndClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer(minLength: 0)

                    HStack {
                        Spacer(minLength: 0)
                        heroStage(width: proxy.size.width, height: proxy.size.height)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 6) {
                        Text(entry.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(entry.subtitle)
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 10)
                }
            }
        }
        .onAppear {
            markOpenedIfNeeded()
        }
    }

    private func markOpenedIfNeeded() {
        guard didMarkOpened == false,
              entry.contentType == .model3D,
              let scannedModel else {
            return
        }

        scannedModel.lastOpenedAt = .now
        try? modelContext.save()
        didMarkOpened = true
    }

    @ViewBuilder
    private func heroStage(width: CGFloat, height: CGFloat) -> some View {
        let stageWidth = min(width - 24, 760)
        let stageHeight = min(height * 0.72, 840)

        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(previewBackgroundStyle)
            .frame(width: stageWidth, height: stageHeight)
            .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
            .matchedGeometryEffect(
                id: entry.signature,
                in: namespace,
                properties: .frame,
                anchor: .center
            )
            .overlay {
                if entry.contentType == .image {
                    imagePreview
                } else {
                    modelPreview
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(AppColors.separator, lineWidth: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: entry.signature)
    }

    private var previewBackgroundStyle: AnyShapeStyle {
        encyclopediaPreviewBackground(for: entry.contentType, colorScheme: colorScheme)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = entry.previewImage {
            EncyclopediaPhotoPreviewRealityView(
                image: image,
                cacheKey: entry.imagePath,
                backgroundColor: encyclopediaPreviewBackgroundColor(for: entry.contentType, colorScheme: colorScheme)
            )
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        } else {
            Image(systemName: entry.previewSymbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(entry.previewSymbolTint)
        }
    }

    @ViewBuilder
    private var modelPreview: some View {
        if let modelPath = entry.modelPath {
            EncyclopediaModelPreviewRealityView(
                modelPath: modelPath,
                scannedModel: scannedModel,
                controller: modelPreviewController,
                backgroundColor: encyclopediaPreviewBackgroundColor(for: entry.contentType, colorScheme: colorScheme)
            )
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        } else if let image = entry.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(18)
        } else {
            Image(systemName: entry.previewSymbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(entry.previewSymbolTint)
        }
    }

    private func commitThumbnailAndClose() {
        guard entry.contentType == .model3D,
              let scannedModel,
              let transform = modelPreviewController.snapshotCurrentTransform() else {
            onClose()
            return
        }

        scannedModel.previewTransformSnapshot = transform

        if let snapshotImage = modelPreviewController.snapshotCurrentImage(),
           let thumbnailData = snapshotImage.pngData() {
            scannedModel.thumbnailData = thumbnailData
        }

        scannedModel.updatedAt = .now
        try? modelContext.save()
        onClose()
    }
}

private func encyclopediaPreviewBackground(
    for contentType: PlacedItemContentType,
    colorScheme: ColorScheme
) -> AnyShapeStyle {
    switch colorScheme {
    case .dark:
        return AnyShapeStyle(AppColors.elevatedSurface)
    case .light:
        switch contentType {
        case .image:
            return AnyShapeStyle(Color(red: 0.94, green: 0.97, blue: 1.0))
        case .model3D:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.96, blue: 1.0), Color(red: 0.84, green: 0.91, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

private func encyclopediaPreviewBackgroundColor(
    for contentType: PlacedItemContentType,
    colorScheme: ColorScheme
) -> UIColor {
    switch colorScheme {
    case .dark:
        return UIColor.tertiarySystemBackground
    case .light:
        switch contentType {
        case .image:
            return UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1)
        case .model3D:
            return UIColor(red: 0.90, green: 0.94, blue: 0.99, alpha: 1)
        }
    }
}

@Observable
final class EncyclopediaModelPreviewController {
    weak var arView: ARView?
    weak var previewEntity: Entity?

    func snapshotCurrentImage() -> UIImage? {
        guard let arView, arView.bounds.isEmpty == false else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: arView.bounds.size, format: format)
        return renderer.image { _ in
            arView.drawHierarchy(in: arView.bounds, afterScreenUpdates: true)
        }
    }

    func snapshotCurrentTransform() -> TransformSnapshot? {
        guard let previewEntity else {
            return nil
        }

        return TransformSnapshot(
            position: previewEntity.position,
            rotation: previewEntity.orientation,
            scale: previewEntity.scale
        )
    }
}

private struct EncyclopediaPhotoPreviewRealityView: UIViewRepresentable {
    let image: UIImage
    let cacheKey: String?
    let backgroundColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(backgroundColor)

        let anchor = AnchorEntity(world: .zero)
        let entity = GoodsEntityFactory.makeGoodsEntity(image: image, cacheKey: cacheKey)
        entity.scale = SIMD3<Float>(repeating: 13.0)
        entity.position = [0, 0, -0.7]
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        context.coordinator.previewEntity = entity
        context.coordinator.configureInitialState(entity: entity)
        context.coordinator.installGestures(on: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator: NSObject {
        weak var previewEntity: Entity?
        private var baseScale: SIMD3<Float> = .one
        private var baseRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        private var basePosition = SIMD3<Float>(0, 0, -0.7)

        func configureInitialState(entity: Entity) {
            baseScale = entity.scale
            baseRotation = entity.orientation
            basePosition = entity.position
        }

        func installGestures(on arView: ARView) {
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

            pinchGesture.delegate = self
            rotationGesture.delegate = self
            panGesture.delegate = self

            arView.addGestureRecognizer(pinchGesture)
            arView.addGestureRecognizer(rotationGesture)
            arView.addGestureRecognizer(panGesture)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let previewEntity else {
                return
            }

            switch gesture.state {
            case .began:
                baseScale = previewEntity.scale
            case .changed:
                let scaleFactor = Float(gesture.scale)
                let nextScale = clampScale(baseScale * scaleFactor)
                previewEntity.scale = nextScale
            default:
                baseScale = previewEntity.scale
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let previewEntity else {
                return
            }

            switch gesture.state {
            case .began:
                baseRotation = previewEntity.orientation
            case .changed:
                let deltaRotation = simd_quatf(angle: -Float(gesture.rotation), axis: [0, 1, 0])
                previewEntity.orientation = deltaRotation * baseRotation
            default:
                baseRotation = previewEntity.orientation
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let previewEntity, let view = gesture.view else {
                return
            }

            switch gesture.state {
            case .began:
                basePosition = previewEntity.position
            case .changed:
                let translation = gesture.translation(in: view)
                previewEntity.position = [
                    basePosition.x + Float(translation.x) * 0.0012,
                    basePosition.y - Float(translation.y) * 0.0012,
                    basePosition.z
                ]
            default:
                basePosition = previewEntity.position
            }
        }

        private func clampScale(_ scale: SIMD3<Float>) -> SIMD3<Float> {
            let minScale: Float = 0.1
            let maxScale: Float = 30.0
            return [
                min(max(scale.x, minScale), maxScale),
                min(max(scale.y, minScale), maxScale),
                min(max(scale.z, minScale), maxScale)
            ]
        }
    }
}

extension EncyclopediaPhotoPreviewRealityView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private struct EncyclopediaModelPreviewRealityView: UIViewRepresentable {
    let modelPath: String
    let scannedModel: ScannedModel?
    let controller: EncyclopediaModelPreviewController
    let backgroundColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator(modelPath: modelPath)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(backgroundColor)

        let anchor = AnchorEntity(world: .zero)
        let entity = makePreviewEntity()
        applyStoredPreviewTransformIfNeeded(to: entity)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        context.coordinator.previewEntity = entity
        context.coordinator.arView = arView
        controller.previewEntity = entity
        controller.arView = arView
        context.coordinator.configureInitialState(entity: entity)
        context.coordinator.installGestures(on: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.previewEntity = context.coordinator.previewEntity
        controller.arView = uiView
    }

    private func makePreviewEntity() -> Entity {
        guard let modelURL = ScannedModelStore.url(forRelativePath: modelPath),
              let entity = try? Entity.load(contentsOf: modelURL) else {
            return placeholderEntity()
        }

        let bounds = entity.visualBounds(relativeTo: entity)
        if bounds.isEmpty == false {
            let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            if maxExtent > 0 {
							let normalizedScale = min(6.5 / maxExtent, 20.0)
                entity.scale = SIMD3<Float>(repeating: normalizedScale)

                let bottomAlignedCenter = SIMD3<Float>(
                    bounds.center.x,
                    bounds.min.y,
                    bounds.center.z
                )
                entity.position = -bottomAlignedCenter * normalizedScale
            }
        }

        return entity
    }

    private func applyStoredPreviewTransformIfNeeded(to entity: Entity) {
        guard let snapshot = scannedModel?.previewTransformSnapshot,
              snapshot != .identity else {
            entity.position = [0, 0, -0.7]
            return
        }

        entity.position = snapshot.position
        entity.orientation = snapshot.quaternion
        entity.scale = snapshot.scale
    }

    private func placeholderEntity() -> Entity {
        let root = Entity()
        let material = SimpleMaterial(color: UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1), roughness: 0.4, isMetallic: false)
        let box = ModelEntity(mesh: .generateBox(size: [0.22, 0.22, 0.22]), materials: [material])
        root.addChild(box)
        return root
    }

    final class Coordinator: NSObject {
        weak var previewEntity: Entity?
        weak var arView: ARView?
        private var baseScale: SIMD3<Float> = .one
        private var baseRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        private var basePosition = SIMD3<Float>(0, 0, -0.7)
        private let modelPath: String

        init(modelPath: String) {
            self.modelPath = modelPath
        }

        func configureInitialState(entity: Entity) {
            baseScale = entity.scale
            baseRotation = entity.orientation
            basePosition = entity.position
        }

        func installGestures(on arView: ARView) {
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

            pinchGesture.delegate = self
            rotationGesture.delegate = self
            panGesture.delegate = self

            arView.addGestureRecognizer(pinchGesture)
            arView.addGestureRecognizer(rotationGesture)
            arView.addGestureRecognizer(panGesture)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let previewEntity else {
                return
            }

            switch gesture.state {
            case .began:
                baseScale = previewEntity.scale
            case .changed:
                let scaleFactor = Float(gesture.scale)
                let nextScale = clampScale(baseScale * scaleFactor)
                previewEntity.scale = nextScale
            default:
                baseScale = previewEntity.scale
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let previewEntity else {
                return
            }

            switch gesture.state {
            case .began:
                baseRotation = previewEntity.orientation
            case .changed:
                let deltaRotation = simd_quatf(angle: -Float(gesture.rotation), axis: [0, 1, 0])
                previewEntity.orientation = deltaRotation * baseRotation
            default:
                baseRotation = previewEntity.orientation
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let previewEntity, let view = gesture.view else {
                return
            }

            switch gesture.state {
            case .began:
                basePosition = previewEntity.position
            case .changed:
                let translation = gesture.translation(in: view)
                previewEntity.position = [
                    basePosition.x + Float(translation.x) * 0.0012,
                    basePosition.y - Float(translation.y) * 0.0012,
                    basePosition.z
                ]
            default:
                basePosition = previewEntity.position
            }
        }

        private func clampScale(_ scale: SIMD3<Float>) -> SIMD3<Float> {
            let minScale: Float = 0.08
            let maxScale: Float = 30.0
            return [
                min(max(scale.x, minScale), maxScale),
                min(max(scale.y, minScale), maxScale),
                min(max(scale.z, minScale), maxScale)
            ]
        }
    }
}

extension EncyclopediaModelPreviewRealityView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private struct EncyclopediaEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let kindLabel: String
    let contentType: PlacedItemContentType
    let imagePath: String?
    let modelPath: String?
    let previewImage: UIImage?
    let previewSymbol: String
    let previewBackground: AnyShapeStyle
    let previewSymbolTint: Color
    let kindLabelBackground: Color
    let kindLabelTextColor: Color
    let signature: String

    init(item: PlacedItem, scannedModelThumbnailMap: [String: Data]) {
        let title = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle: String
        let subtitle: String
        let kindLabel: String
        let previewImage: UIImage?
        let previewSymbol: String
        let previewBackground: AnyShapeStyle
        let previewSymbolTint: Color
        let kindLabelBackground: Color
        let kindLabelTextColor: Color

        contentType = item.contentType
        switch item.contentType {
        case .image:
            fallbackTitle = "写真オブジェクト"
            subtitle = "写真から作成"
            kindLabel = "PHOTO"
            imagePath = item.imagePath
            modelPath = nil
            previewImage = ImageStore.load(path: item.imagePath)
            previewSymbol = "photo"
            previewBackground = AnyShapeStyle(Color(red: 0.94, green: 0.97, blue: 1.0))
            previewSymbolTint = Color.blue
            kindLabelBackground = Color.blue.opacity(0.14)
            kindLabelTextColor = Color.blue
        case .model3D:
            fallbackTitle = "3Dモデル"
            subtitle = "3Dモデル"
            kindLabel = "3D"
            imagePath = nil
            modelPath = item.modelPath
            if let modelPath,
               let thumbnailData = scannedModelThumbnailMap[modelPath] {
                previewImage = UIImage(data: thumbnailData)
            } else {
                previewImage = nil
            }
            previewSymbol = "cube.fill"
            previewBackground = AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.93, green: 0.96, blue: 1.0), Color(red: 0.84, green: 0.91, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            previewSymbolTint = Color.indigo
            kindLabelBackground = Color.indigo.opacity(0.14)
            kindLabelTextColor = Color.indigo
        }

        let resolvedTitle = (title?.isEmpty == false ? title : nil) ?? fallbackTitle
        self.title = resolvedTitle
        self.subtitle = subtitle
        self.kindLabel = kindLabel
        self.previewImage = previewImage
        self.previewSymbol = previewSymbol
        self.previewBackground = previewBackground
        self.previewSymbolTint = previewSymbolTint
        self.kindLabelBackground = kindLabelBackground
        self.kindLabelTextColor = kindLabelTextColor

        let resolvedSignature = item.encyclopediaSignature
        self.signature = resolvedSignature
        self.id = resolvedSignature
    }
}

private extension PlacedItem {
    var encyclopediaSignature: String {
        switch contentType {
        case .image:
            if let url = ImageStore.url(for: imagePath),
               let data = try? Data(contentsOf: url) {
                return "image:" + data.sha256Hex
            }

            return "image:path:\(imagePath)"
        case .model3D:
            guard let modelPath else {
                return "model:missing:\(id.uuidString)"
            }

            if let url = ScannedModelStore.url(forRelativePath: modelPath),
               let data = try? Data(contentsOf: url) {
                return "model:" + data.sha256Hex
            }

            return "model:path:\(modelPath)"
        }
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).compactMap { String(format: "%02x", $0) }.joined()
    }
}
