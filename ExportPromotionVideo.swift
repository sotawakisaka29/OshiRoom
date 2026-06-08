import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import SwiftUI
import VideoToolbox

@main
struct ExportPromotionVideo {
    static func main() async throws {
        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("My_Oshi_Room_Promo_15s.mp4")

        try? FileManager.default.removeItem(at: outputURL)

        let canvasSize = CGSize(width: 1080, height: 1920)
        let framesPerSecond = 30
        let duration: Double = 15
        let totalFrames = Int(duration * Double(framesPerSecond))

        let encoderOrder: [CMVideoCodecType] = [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC]
        var compressedSamples: [CMSampleBuffer] = []
        var encoderError: Error?

        for codec in encoderOrder {
            do {
                compressedSamples = try await encodeFrames(
                    codec: codec,
                    size: canvasSize,
                    framesPerSecond: framesPerSecond,
                    totalFrames: totalFrames
                )
                encoderError = nil
                break
            } catch {
                encoderError = error
            }
        }

        if compressedSamples.isEmpty {
            throw encoderError ?? NSError(domain: "ExportPromotionVideo", code: 3, userInfo: [NSLocalizedDescriptionKey: "動画の圧縮に失敗しました。"])
        }

        guard let firstSample = compressedSamples.first,
              let formatDescription = CMSampleBufferGetFormatDescription(firstSample) else {
            throw NSError(domain: "ExportPromotionVideo", code: 4, userInfo: [NSLocalizedDescriptionKey: "書き出し用のフォーマット情報を取得できませんでした。"])
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw NSError(domain: "ExportPromotionVideo", code: 5, userInfo: [NSLocalizedDescriptionKey: "動画入力を追加できませんでした。"])
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "ExportPromotionVideo", code: 6, userInfo: [NSLocalizedDescriptionKey: "書き出しを開始できませんでした。"])
        }
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(firstSample))

        for sampleBuffer in compressedSamples {
            while input.isReadyForMoreMediaData == false {
                usleep(1_000)
            }

            guard input.append(sampleBuffer) else {
                throw writer.error ?? NSError(domain: "ExportPromotionVideo", code: 7, userInfo: [NSLocalizedDescriptionKey: "動画フレームを書き込めませんでした。"])
            }
        }

        input.markAsFinished()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        print(outputURL.path)
    }
}

@MainActor
private func encodeFrames(
    codec: CMVideoCodecType,
    size: CGSize,
    framesPerSecond: Int,
    totalFrames: Int
) throws -> [CMSampleBuffer] {
    let compressor = try FrameCompressor(
        codec: codec,
        size: size,
        framesPerSecond: framesPerSecond
    )

    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
    var compressedSamples: [CMSampleBuffer] = []

    for frameIndex in 0..<totalFrames {
        let time = Double(frameIndex) / Double(framesPerSecond)
        let frameView = PromotionFrameView(playhead: time)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: frameView)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)

        guard let cgImage = renderer.cgImage,
              let pixelBuffer = makePixelBuffer(from: cgImage, size: size) else {
            throw NSError(domain: "ExportPromotionVideo", code: 20, userInfo: [NSLocalizedDescriptionKey: "フレームを画像化できませんでした。"])
        }

        try compressor.encode(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(framesPerSecond)),
            duration: frameDuration
        )

        guard let sampleBuffer = compressor.drainSampleBuffer() else {
            throw NSError(domain: "ExportPromotionVideo", code: 21, userInfo: [NSLocalizedDescriptionKey: "圧縮済みフレームを取得できませんでした。"])
        }
        compressedSamples.append(sampleBuffer)
    }

    try compressor.finish()
    return compressedSamples
}

private func makePixelBuffer(
    from cgImage: CGImage,
    size: CGSize
) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?

    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVPixelBufferCGImageCompatibilityKey as String: true
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32ARGB,
        attributes as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess else {
        return nil
    }

    guard let buffer = pixelBuffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
        return nil
    }

    guard let context = CGContext(
        data: baseAddress,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        return nil
    }

    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
    return buffer
}

private final class FrameCompressor {
    private let session: VTCompressionSession
    private let context: CompressionContext
    private let semaphore = DispatchSemaphore(value: 0)
    private var pendingSampleBuffers: [CMSampleBuffer] = []
    private(set) var lastError: Error?

    init(codec: CMVideoCodecType, size: CGSize, framesPerSecond: Int) throws {
        let width = Int32(size.width.rounded())
        let height = Int32(size.height.rounded())

        let context = CompressionContext()
        var sessionOut: VTCompressionSession?
        let encoderSpecification: [CFString: Any] = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanFalse as Any,
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanFalse as Any
        ]
        let outputCallback: VTCompressionOutputCallback = { outputCallbackRefCon, _, status, _, sampleBuffer in
            guard let outputCallbackRefCon else {
                return
            }

            let context = Unmanaged<CompressionContext>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
            guard let compressor = context.compressor else {
                return
            }

            if status != noErr {
                compressor.lastError = NSError(
                    domain: "ExportPromotionVideo",
                    code: Int(status),
                    userInfo: [NSLocalizedDescriptionKey: "動画の圧縮に失敗しました。"]
                )
                compressor.semaphore.signal()
                return
            }

            if let sampleBuffer {
                compressor.pendingSampleBuffers.append(sampleBuffer)
            } else {
                compressor.lastError = NSError(
                    domain: "ExportPromotionVideo",
                    code: 30,
                    userInfo: [NSLocalizedDescriptionKey: "圧縮済みサンプルを受け取れませんでした。"]
                )
            }

            compressor.semaphore.signal()
        }

        let createStatus = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codec,
            encoderSpecification: encoderSpecification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(context).toOpaque(),
            compressionSessionOut: &sessionOut
        )

        guard createStatus == noErr, let session = sessionOut else {
            throw NSError(
                domain: "ExportPromotionVideo",
                code: Int(createStatus),
                userInfo: [NSLocalizedDescriptionKey: "圧縮セッションを作成できませんでした。"]
            )
        }

        self.session = session
        self.context = context
        self.context.compressor = self

        let frameRate: CFNumber = NSNumber(value: framesPerSecond)
        let bitrate: CFNumber = NSNumber(value: 12_000_000)
        let keyFrameInterval: CFNumber = NSNumber(value: framesPerSecond)

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyFrameInterval)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        if codec == kCMVideoCodecType_H264 {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        } else if codec == kCMVideoCodecType_HEVC {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        }

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            throw NSError(
                domain: "ExportPromotionVideo",
                code: Int(prepareStatus),
                userInfo: [NSLocalizedDescriptionKey: "圧縮の準備に失敗しました。"]
            )
        }
    }

    func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, duration: CMTime) throws {
        let encodeStatus = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        guard encodeStatus == noErr else {
            throw NSError(
                domain: "ExportPromotionVideo",
                code: Int(encodeStatus),
                userInfo: [NSLocalizedDescriptionKey: "フレームを圧縮できませんでした。"]
            )
        }

        semaphore.wait()
        if let lastError {
            throw lastError
        }
    }

    func drainSampleBuffer() -> CMSampleBuffer? {
        guard pendingSampleBuffers.isEmpty == false else {
            return nil
        }

        return pendingSampleBuffers.removeFirst()
    }

    func finish() throws {
        let completeStatus = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard completeStatus == noErr else {
            throw NSError(
                domain: "ExportPromotionVideo",
                code: Int(completeStatus),
                userInfo: [NSLocalizedDescriptionKey: "圧縮セッションを終了できませんでした。"]
            )
        }
    }
}

private final class CompressionContext {
    weak var compressor: FrameCompressor?
}

private struct PromotionFrameView: View {
    let playhead: Double

    var body: some View {
        ZStack {
            promoBackground

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                heroSection
                    .opacity(sceneOpacity(playhead, start: 0.0, end: 4.2))

                createRoomSection
                    .opacity(sceneOpacity(playhead, start: 3.4, end: 7.8))

                addGoodsSection
                    .opacity(sceneOpacity(playhead, start: 7.0, end: 11.7))

                finalSection
                    .opacity(sceneOpacity(playhead, start: 11.0, end: 15.0))

                Spacer(minLength: 28)
            }

            progressBar
        }
    }

    private var promoBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.10),
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.16, green: 0.10, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PromoGrid()
                .opacity(0.24)

            PromoGlow(
                color: Color(red: 0.98, green: 0.70, blue: 0.26),
                size: 260,
                x: 170 + CGFloat(sin(playhead * 0.75)) * 18,
                y: 320 + CGFloat(cos(playhead * 0.62)) * 10,
                opacity: 0.34
            )

            PromoGlow(
                color: Color(red: 0.40, green: 0.72, blue: 0.96),
                size: 300,
                x: 900 + CGFloat(cos(playhead * 0.48)) * 20,
                y: 340 + CGFloat(sin(playhead * 0.51)) * 14,
                opacity: 0.24
            )

            PromoGlow(
                color: Color(red: 0.71, green: 0.48, blue: 0.98),
                size: 340,
                x: 760 + CGFloat(sin(playhead * 0.32)) * 24,
                y: 1520 + CGFloat(cos(playhead * 0.40)) * 16,
                opacity: 0.22
            )
        }
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text("AR空間に")
                    .font(.system(size: 66, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("自分の好きな世界が広がる")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("推しの写真、グッズ、3Dモデルを\nひとつの部屋にまとめて飾れます。")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.80))
            }
            .padding(.horizontal, 76)
            .offset(y: CGFloat(1 - easeInOut(clamp(playhead / 1.0))) * 24)

            PromoShowcaseCard(progress: easeInOut(clamp((playhead - 0.4) / 1.6)))
                .frame(height: 520)
                .padding(.horizontal, 48)
                .shadow(color: .black.opacity(0.20), radius: 32, y: 16)

            PromoBadge(
                title: "My Oshi Room",
                subtitle: "App Storeではこの名前で表示されます。"
            )
            .padding(.horizontal, 72)
        }
    }

    private var createRoomSection: some View {
        let stage = easeInOut(clamp((playhead - 3.55) / 1.45))

        return VStack(spacing: 18) {
            PromoSectionHeader(
                step: "01 / 04",
                title: "まずは部屋を作る",
                subtitle: "部屋名をつけるだけで、AR空間の土台ができます。"
            )
            .padding(.horizontal, 64)
            .offset(y: CGFloat(1 - stage) * 28)

            PromoRoomCard()
                .padding(.horizontal, 56)
                .scaleEffect(0.98 + 0.02 * stage)
                .shadow(color: .black.opacity(0.16), radius: 24, y: 12)

            PromoTemplateStrip()
                .padding(.horizontal, 56)
        }
    }

    private var addGoodsSection: some View {
        let stage = easeInOut(clamp((playhead - 7.15) / 1.55))

        return VStack(spacing: 18) {
            PromoSectionHeader(
                step: "02 / 04",
                title: "写真から、すぐグッズ化",
                subtitle: "カメラや写真を使って、推しのグッズを部屋に追加できます。"
            )
            .padding(.horizontal, 64)

            HStack(spacing: 18) {
                PromoActionCard(
                    icon: "photo.on.rectangle",
                    title: "写真を選択",
                    subtitle: "お気に入りの一枚から"
                )
                PromoActionCard(
                    icon: "camera",
                    title: "カメラで撮影",
                    subtitle: "今この瞬間を残す"
                )
            }
            .padding(.horizontal, 56)

            ZStack(alignment: .bottomTrailing) {
                PromoCutoutCard(progress: stage)
                    .frame(height: 320)

                PromoMiniBubble(
                    text: "背景除去で\nアクスタ風に",
                    symbol: "sparkles",
                    color: Color(red: 0.98, green: 0.70, blue: 0.26)
                )
                .offset(x: -24, y: 20)
            }
            .padding(.horizontal, 56)

            PromoActionCard(
                icon: "cube.transparent",
                title: "3Dモデルを選択",
                subtitle: "スキャン済みモデルも飾れる"
            )
            .padding(.horizontal, 56)
        }
    }

    private var finalSection: some View {
        let stage = easeInOut(clamp((playhead - 11.1) / 1.4))

        return VStack(spacing: 20) {
            PromoBadge(
                title: "My Oshi Room",
                subtitle: "AR空間に、好きな世界を育てよう。"
            )
            .padding(.horizontal, 72)

            VStack(spacing: 10) {
                Text("部屋、グッズ、3Dモデルをひとつに。")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .offset(y: CGFloat(1 - stage) * 18)

                Text("推し活が、そのまま飾れるAR体験になります。")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .padding(.horizontal, 72)

            PromoShowcaseCard(progress: 0.92)
                .frame(height: 440)
                .padding(.horizontal, 56)

            PromoCTA(
                title: "My Oshi Room",
                subtitle: "App Storeで会いましょう"
            )
            .padding(.horizontal, 72)

            Text("AR空間に自分の好きな世界が広がる")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
        }
    }

    private var progressBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    Text("0:15")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.60))
                    Spacer()
                    Text("My Oshi Room")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                }

                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.70, blue: 0.26),
                                            Color(red: 0.40, green: 0.72, blue: 0.96)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: proxy.size.width * clamp(playhead / 15.0))
                        }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 28)
        }
    }
}

private struct PromoGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let verticalStep: CGFloat = max(28, size.width / 10)
            let horizontalStep: CGFloat = max(28, size.height / 12)

            for x in stride(from: 0, through: size.width, by: verticalStep) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for y in stride(from: 0, through: size.height, by: horizontalStep) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
        }
    }
}

private struct PromoGlow: View {
    let color: Color
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let opacity: Double

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.25)
            .opacity(opacity)
            .position(x: x, y: y)
            .blendMode(.screen)
    }
}

private struct PromoShowcaseCard: View {
    let progress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            VStack(spacing: 22) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .frame(height: 72)
                    .overlay {
                        Text("AR Shelf")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                    }
                    .padding(.horizontal, 30)

                HStack(spacing: 18) {
                    PromoMiniPanel(
                        title: "写真から",
                        subtitle: "アクスタ風に",
                        icon: "photo",
                        color: Color(red: 0.98, green: 0.70, blue: 0.26),
                        progress: progress
                    )
                    PromoMiniPanel(
                        title: "3Dモデル",
                        subtitle: "そのまま飾る",
                        icon: "cube.transparent",
                        color: Color(red: 0.40, green: 0.72, blue: 0.96),
                        progress: 1 - progress * 0.25
                    )
                }
                .padding(.horizontal, 20)

                HStack(spacing: 14) {
                    ForEach(PromoShelfTemplate.allCases) { template in
                        VStack(spacing: 8) {
                            Image(systemName: template.symbolName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(template.tint)
                                .frame(width: 42, height: 42)
                                .background(template.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(template.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 28)
                .offset(y: progress * -2)
            }
            .padding(.vertical, 20)
        }
    }
}

private struct PromoMiniPanel: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.95), color.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 138)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .offset(y: 8 * (1 - progress))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct PromoRoomCard: View {
    var body: some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 116, height: 116)
                .overlay {
                    Image(systemName: "house.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.88))
                }

            VStack(alignment: .leading, spacing: 10) {
                Button { } label: {
                    HStack(spacing: 6) {
                        Text("ライブ記念ルーム")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)

                Text("1台の棚")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text("最終更新日: 2026/06/08 21:00")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack {
                    Label("追加済みオブジェクト一覧", systemImage: "rectangle.stack")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.70))
                    Spacer()
                    Text("8")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Spacer()
        }
        .padding(18)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct PromoTemplateStrip: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("「ライブ記念ルーム」みたいに、\n思い出ごとに分けて整理できます。")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(PromoShelfTemplate.allCases) { template in
                    HStack(spacing: 14) {
                        Image(systemName: template.symbolName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(template.tint)
                            .frame(width: 52, height: 52)
                            .background(template.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(template.subtitle)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Spacer()

                        if template == .wood {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
    }
}

private struct PromoActionCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct PromoCutoutCard: View {
    let progress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.93, blue: 0.80),
                            Color(red: 0.92, green: 0.78, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )

            Circle()
                .fill(Color.white.opacity(0.26))
                .frame(width: 110, height: 110)
                .offset(x: -96, y: -60)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.98, green: 0.70, blue: 0.26))
                .frame(width: 176, height: 240)
                .overlay {
                    VStack(spacing: 18) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white.opacity(0.94))

                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.54))
                            .frame(width: 98, height: 148)
                            .overlay {
                                Text("Oshi")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.58, green: 0.30, blue: 0.10))
                            }
                    }
                }
                .rotationEffect(.degrees(-6 + 8 * (1 - progress)))
                .offset(x: -36 + 24 * progress, y: -12 + 10 * (1 - progress))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 2)
                .frame(width: 248, height: 140)
                .rotationEffect(.degrees(10))
                .offset(x: 60, y: 76)

            VStack(alignment: .leading, spacing: 10) {
                Text("背景除去")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.56))
                Text("アクスタ風の\nグッズが完成")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 30)
            .offset(y: 84)
        }
    }
}

private struct PromoBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct PromoCTA: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.70, blue: 0.26).opacity(0.24),
                    Color(red: 0.40, green: 0.72, blue: 0.96).opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct PromoMiniBubble: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct PromoSectionHeader: View {
    let step: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))
            Text(title)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PromoShelfTemplate: String, CaseIterable, Identifiable {
    case wood, glass, wall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wood: "木製棚"
        case .glass: "ガラスケース"
        case .wall: "壁掛け棚"
        }
    }

    var subtitle: String {
        switch self {
        case .wood: "あたたかい木目風の展示棚"
        case .glass: "透明感のあるコレクションケース"
        case .wall: "省スペースな壁面ディスプレイ"
        }
    }

    var symbolName: String {
        switch self {
        case .wood: "books.vertical"
        case .glass: "shippingbox"
        case .wall: "rectangle.portrait.on.rectangle.portrait"
        }
    }

    var tint: Color {
        switch self {
        case .wood:
            Color(red: 0.58, green: 0.42, blue: 0.28)
        case .glass:
            Color(red: 0.48, green: 0.66, blue: 0.78)
        case .wall:
            Color(red: 0.54, green: 0.56, blue: 0.60)
        }
    }
}

private func clamp(_ value: Double) -> Double {
    max(0, min(1, value))
}

private func easeInOut(_ value: Double) -> Double {
    let clamped = clamp(value)
    return clamped * clamped * (3 - 2 * clamped)
}

private func sceneOpacity(_ playhead: Double, start: Double, end: Double) -> Double {
    let fade: Double = 0.35

    if playhead < start - fade || playhead > end + fade {
        return 0
    }

    if playhead < start {
        return easeInOut(clamp((playhead - (start - fade)) / fade))
    }

    if playhead > end {
        return 1 - easeInOut(clamp((playhead - end) / fade))
    }

    return 1
}
