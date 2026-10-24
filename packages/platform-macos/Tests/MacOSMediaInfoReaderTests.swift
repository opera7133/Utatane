import AppKit
import AVFoundation
import Foundation
import Testing
import UtataneNativeSaori
@testable import UtatanePlatformMacOS

@Test func `MediaInfo reads generated image and audio files without playing them`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let image = root.appending(path: "画像.png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: image)
    let reader = MacOSMediaInfoReader()
    let png = try reader.read(image)
    #expect(png.kind == "image")
    #expect(png.values["width"] == "3")
    #expect(png.values["height"] == "2")
    let audio = root.appending(path: "無音.wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800))
    buffer.frameLength = 800
    for i in 0 ..< 800 {
        buffer.floatChannelData?[0][i] = 0
    }
    do {
        let file = try AVAudioFile(forWriting: audio, settings: format.settings)
        try file.write(from: buffer)
    }
    let wav = try reader.read(audio)
    #expect(wav.kind == "audio")
    #expect(wav.values["duration"] == "100")
    let broken = root.appending(path: "broken.bin")
    try Data([1, 2, 3]).write(to: broken)
    #expect(try reader.read(broken).kind == "")
}

@Test func `MediaInfo reads exported audio tags and video dimensions`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let wave = root.appending(path: "source.wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
    buffer.frameLength = 4410
    for i in 0 ..< 4410 {
        buffer.floatChannelData?[0][i] = 0
    }
    do { let file = try AVAudioFile(forWriting: wave, settings: format.settings); try file.write(from: buffer) }
    let exported = root.appending(path: "tags.m4a")
    let export = try #require(AVAssetExportSession(asset: AVURLAsset(url: wave), presetName: AVAssetExportPresetAppleM4A))
    let entries: [(AVMetadataIdentifier, String)] = [(.commonIdentifierTitle, "曲名"), (.commonIdentifierArtist, "作者"),
                                                     (.commonIdentifierAlbumName, "アルバム"), (.commonIdentifierCreationDate, "2026-10-24")]
    export.metadata = entries.map { identifier, text in
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = text as NSString
        return item
    }
    try await export.export(to: exported, as: .m4a)
    let tags = try MacOSMediaInfoReader().read(exported)
    #expect(tags.kind == "audio")
    #expect(tags.values["title"] == "曲名")
    #expect(tags.values["artist"] == "作者")
    #expect(tags.values["album"] == "アルバム")
    #expect(tags.values["year"] == "2026")
    let movie = root.appending(path: "video.mov")
    let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 16])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 16
    ])
    writer.add(input)
    try #require(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var pixel: CVPixelBuffer?
    #expect(CVPixelBufferCreate(nil, 32, 16, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess)
    let frame = try #require(pixel)
    CVPixelBufferLockBaseAddress(frame, [])
    memset(CVPixelBufferGetBaseAddress(frame), 0, CVPixelBufferGetDataSize(frame))
    CVPixelBufferUnlockBaseAddress(frame, [])
    // Completion is driven by the writer's readiness callback, not a sleep.
    let appended: Bool = await withCheckedContinuation { continuation in
        let completion = VideoFrameCompletion(continuation)
        let queue = DispatchQueue(label: "utatane.test.video-writer")
        queue.asyncAfter(deadline: .now() + 20) {
            completion.finish(false)
        }
        input.requestMediaDataWhenReady(on: queue) {
            guard input.isReadyForMoreMediaData, completion.isPending else { return }
            let success = adaptor.append(frame, withPresentationTime: .zero)
            input.markAsFinished()
            completion.finish(success)
        }
    }
    try #require(appended)
    writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 30))
    await writer.finishWriting()
    #expect(writer.status == .completed)
    let video = try MacOSMediaInfoReader().read(movie)
    #expect(video.kind == "video")
    #expect(video.values["width"] == "32")
    #expect(video.values["height"] == "16")
}

/// A writer that fails to become ready must fail the test, not hang CI.
private final class VideoFrameCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    var isPending: Bool {
        lock.withLock { continuation != nil }
    }

    func finish(_ success: Bool) {
        let waiting = lock.withLock {
            let value = continuation
            continuation = nil
            return value
        }
        waiting?.resume(returning: success)
    }
}
