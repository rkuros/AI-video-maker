import Cocoa
import FlutterMacOS
import AVFoundation
import CoreImage
import CoreML
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    CoreMLDenoiserChannel.register(with: flutterViewController)

    super.awakeFromNib()
  }
}

final class CoreMLDenoiserChannel {
  struct DenoiseError: Error {
    let code: String
    let message: String
    let details: String?
  }

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "video_editor/coreml_denoise",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "denoiseVideo" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String,
            let startMs = args["startMs"] as? Int,
            let durationMs = args["durationMs"] as? Int,
            let modelPath = args["modelPath"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Invalid arguments for denoiseVideo",
            details: call.arguments
          )
        )
        return
      }

      let inputURL = URL(fileURLWithPath: inputPath)
      let outputURL = URL(fileURLWithPath: outputPath)
      let modelURL = URL(fileURLWithPath: modelPath)

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try self.denoiseVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            startMs: startMs,
            durationMs: durationMs,
            modelURL: modelURL
          )
          result(nil)
        } catch let error as DenoiseError {
          result(
            FlutterError(
              code: error.code,
              message: error.message,
              details: error.details
            )
          )
        } catch {
          result(
            FlutterError(
              code: "coreml_denoise_failed",
              message: "CoreML denoise failed",
              details: "\(error)"
            )
          )
        }
      }
    }
  }

  private static func loadModel(at url: URL) throws -> VNCoreMLModel {
    let compiledURL: URL
    if url.pathExtension == "mlmodel" {
      compiledURL = try MLModel.compileModel(at: url)
    } else {
      compiledURL = url
    }

    let config = MLModelConfiguration()
    config.computeUnits = .all

    let model = try MLModel(contentsOf: compiledURL, configuration: config)
    return try VNCoreMLModel(for: model)
  }

  private static func denoiseVideo(
    inputURL: URL,
    outputURL: URL,
    startMs: Int,
    durationMs: Int,
    modelURL: URL
  ) throws {
    if durationMs <= 0 {
      throw DenoiseError(
        code: "invalid_duration",
        message: "durationMs must be > 0",
        details: "\(durationMs)"
      )
    }

    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let asset = AVAsset(url: inputURL)
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      throw DenoiseError(code: "no_video", message: "No video track", details: inputURL.path)
    }

    let vnModel = try loadModel(at: modelURL)
    let request = VNCoreMLRequest(model: vnModel)
    request.imageCropAndScaleOption = .scaleFill

    let startTime = CMTime(value: CMTimeValue(startMs), timescale: 1000)
    let duration = CMTime(value: CMTimeValue(durationMs), timescale: 1000)
    let timeRange = CMTimeRange(start: startTime, duration: duration)

    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = timeRange

    let videoOutputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
    videoOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(videoOutput) else {
      throw DenoiseError(code: "reader_video", message: "Cannot add video output", details: nil)
    }
    reader.add(videoOutput)

    var audioOutput: AVAssetReaderTrackOutput? = nil
    if let audioTrack = asset.tracks(withMediaType: .audio).first {
      let aOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
      aOut.alwaysCopiesSampleData = false
      if reader.canAdd(aOut) {
        reader.add(aOut)
        audioOutput = aOut
      }
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

    let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let width = Int(abs(naturalSize.width))
    let height = Int(abs(naturalSize.height))

    let videoInputSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoInputSettings)
    videoInput.expectsMediaDataInRealTime = false
    videoInput.transform = videoTrack.preferredTransform

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
      ]
    )

    guard writer.canAdd(videoInput) else {
      throw DenoiseError(code: "writer_video", message: "Cannot add video input", details: nil)
    }
    writer.add(videoInput)

    var audioInput: AVAssetWriterInput? = nil
    if audioOutput != nil {
      let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
      aIn.expectsMediaDataInRealTime = false
      if writer.canAdd(aIn) {
        writer.add(aIn)
        audioInput = aIn
      }
    }

    guard reader.startReading() else {
      throw DenoiseError(code: "reader_start", message: "Reader failed to start", details: reader.error?.localizedDescription)
    }

    guard writer.startWriting() else {
      throw DenoiseError(code: "writer_start", message: "Writer failed to start", details: writer.error?.localizedDescription)
    }
    writer.startSession(atSourceTime: .zero)

    var firstVideoPTS: CMTime? = nil
    var videoDone = false
    var audioDone = (audioOutput == nil || audioInput == nil)

    while reader.status == .reading && !(videoDone && audioDone) {
      if !videoDone, videoInput.isReadyForMoreMediaData {
        if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
          let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
          if firstVideoPTS == nil { firstVideoPTS = pts }
          let outPTS = pts - (firstVideoPTS ?? pts)

          guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw DenoiseError(code: "no_pixelbuffer", message: "Missing pixel buffer", details: nil)
          }

          let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
          try handler.perform([request])

          guard let results = request.results, !results.isEmpty else {
            throw DenoiseError(code: "no_results", message: "CoreML returned no results", details: nil)
          }

          let outputPixelBuffer: CVPixelBuffer?
          if let obs = results.first as? VNPixelBufferObservation {
            outputPixelBuffer = obs.pixelBuffer
          } else if let obs = results.first as? VNCoreMLFeatureValueObservation,
                    obs.featureValue.type == .image,
                    let pb = obs.featureValue.imageBufferValue {
            outputPixelBuffer = pb
          } else {
            outputPixelBuffer = nil
          }

          guard let denoised = outputPixelBuffer else {
            throw DenoiseError(code: "unsupported_output", message: "Unsupported CoreML output type", details: "\(type(of: results.first!))")
          }

          if !adaptor.append(denoised, withPresentationTime: outPTS) {
            throw DenoiseError(code: "append_failed", message: "Failed to append video frame", details: writer.error?.localizedDescription)
          }
        } else {
          videoDone = true
          videoInput.markAsFinished()
        }
      }

      if !audioDone, let aOut = audioOutput, let aIn = audioInput, aIn.isReadyForMoreMediaData {
        if let audioSample = aOut.copyNextSampleBuffer() {
          if !aIn.append(audioSample) {
            throw DenoiseError(code: "append_audio_failed", message: "Failed to append audio", details: writer.error?.localizedDescription)
          }
        } else {
          audioDone = true
          aIn.markAsFinished()
        }
      }
    }

    if reader.status == .failed {
      throw DenoiseError(code: "reader_failed", message: "Reader failed", details: reader.error?.localizedDescription)
    }

    if reader.status == .cancelled {
      throw DenoiseError(code: "reader_cancelled", message: "Reader cancelled", details: nil)
    }

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 60 * 60)

    if writer.status == .failed {
      throw DenoiseError(code: "writer_failed", message: "Writer failed", details: writer.error?.localizedDescription)
    }
  }
}
