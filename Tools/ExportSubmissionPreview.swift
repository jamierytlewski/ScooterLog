import AVFoundation
import Foundation

/// Converts timestamped simulator scenes into Apple's 886 x 1920 portrait preview format.
@main
enum ExportSubmissionPreview {
    static func main() async throws {
        guard CommandLine.arguments.count == 5,
              let epoch = Double(CommandLine.arguments[3]) else {
            throw failure("Usage: export-preview raw.mov capture.log recording-start-epoch output.mp4")
        }
        let source = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let log = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let scenes = try log.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("APP_STORE_SCENE ") }
            .map { line -> Double in
                guard let timestamp = line.split(separator: " ").last.flatMap({ Double($0) }) else {
                    throw failure("Invalid scene timestamp: \(line)")
                }
                return timestamp - epoch + 0.5
            }
        guard scenes.count == 6 else { throw failure("Expected six captured scenes, found \(scenes.count).") }
        let sourceDuration = try await source.load(.duration)
        let sourceTrack = try await source.loadTracks(withMediaType: .video).first
        guard let sourceTrack else { throw failure("Recording has no video track.") }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video,
                                                     preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw failure("Could not create the video composition.")
        }
        for (index, start) in scenes.enumerated() {
            guard start >= 0, start + 4 <= sourceDuration.seconds else {
                throw failure("Scene \(index) extends outside the recording.")
            }
            try track.insertTimeRange(
                CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                            duration: CMTime(seconds: 4, preferredTimescale: 600)),
                of: sourceTrack, at: CMTime(seconds: Double(index * 4), preferredTimescale: 600))
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[4])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw failure("Output already exists: \(output.path)")
        }
        // A silent stereo AAC track avoids copyrighted music and meets the preview audio format.
        let audioURL = output.deletingPathExtension().appendingPathExtension("wav")
        guard !FileManager.default.fileExists(atPath: audioURL.path) else {
            throw failure("Temporary audio file already exists: \(audioURL.path)")
        }
        try silentWAV(seconds: scenes.count * 4).write(to: audioURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let audioAsset = AVURLAsset(url: audioURL)
        guard let audioSource = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw failure("Could not create the silent audio track.")
        }
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: composition.duration),
                                       of: audioSource, at: .zero)

        let size = try await sourceTrack.load(.naturalSize)
        let scale = min(886 / size.width, 1920 / size.height)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(CGAffineTransform(scaleX: scale, y: scale).concatenating(
            CGAffineTransform(translationX: (886 - size.width * scale) / 2,
                              y: (1920 - size.height * scale) / 2)), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 886, height: 1920)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOutput.videoComposition = videoComposition
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(videoOutput), reader.canAdd(audioOutput) else {
            throw failure("Cannot decode the preview composition.")
        }
        reader.add(videoOutput)
        reader.add(audioOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 886,
            AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 11_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000
        ])
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw failure("Cannot encode the required H.264 and AAC formats.")
        }
        writer.add(videoInput)
        writer.add(audioInput)
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
                                                         sourcePixelBufferAttributes: nil)
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? failure("Could not start preview export.")
        }
        writer.startSession(atSourceTime: .zero)
        var videoDone = false, audioDone = false
        var upcomingVideo = videoOutput.copyNextSampleBuffer()
        var currentVideo: CMSampleBuffer?
        var frameIndex: Int64 = 0
        let frameCount = Int64(scenes.count * 4 * 30)
        while !videoDone || !audioDone {
            guard writer.status == .writing, reader.status != .failed else {
                throw writer.error ?? reader.error ?? failure("Preview export stopped unexpectedly.")
            }
            if !videoDone, videoInput.isReadyForMoreMediaData {
                if frameIndex < frameCount {
                    let time = CMTime(value: frameIndex, timescale: 30)
                    // Simulator recordings omit unchanged frames; repeat them to produce true 30 fps.
                    while let sample = upcomingVideo, CMSampleBufferGetPresentationTimeStamp(sample) <= time {
                        currentVideo = sample
                        upcomingVideo = videoOutput.copyNextSampleBuffer()
                    }
                    guard let currentVideo, let buffer = CMSampleBufferGetImageBuffer(currentVideo),
                          pixels.append(buffer, withPresentationTime: time) else {
                        throw writer.error ?? reader.error ?? failure("Could not write preview frame \(frameIndex).")
                    }
                    frameIndex += 1
                } else {
                    videoInput.markAsFinished()
                    videoDone = true
                }
            }
            if !audioDone, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else {
                        throw writer.error ?? failure("Could not write a preview audio sample.")
                    }
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        writer.endSession(atSourceTime: composition.duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? failure("Preview export did not complete.")
        }
        print("Exported \(scenes.count * 4)s, 886 x 1920, 30 fps H.264 High 4.0 with stereo AAC: \(output.path)")
    }

    private static func silentWAV(seconds: Int) -> Data {
        let byteCount = UInt32(seconds * 48_000 * 2 * 2)
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        append(byteCount + 36)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(2))
        append(UInt32(48_000))
        append(UInt32(48_000 * 4))
        append(UInt16(4))
        append(UInt16(16))
        data.append(Data("data".utf8))
        append(byteCount)
        data.append(Data(repeating: 0, count: Int(byteCount)))
        return data
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SubmissionPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
