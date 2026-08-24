import AVFoundation
import Flutter
import MediaPipeTasksVision
import UIKit

/// Runs MediaPipe Pose Landmarker over a recorded clip in VIDEO mode and streams
/// the landmark sequence back to Dart — the iOS twin of the Android Kotlin
/// plugin. Same channels, same message shapes, so the shared Dart layer and the
/// cross-language golden fixtures apply unchanged.
///
/// - Method channel `pose_landmarker/methods`: `cancel` and `grabFrames`.
/// - Event channel `pose_landmarker/progress`: `onListen` starts a run; progress
///   maps `{framesProcessed,totalFrames}` arrive during it and a final
///   `{framesProcessed,totalFrames,frames}` closes it.
///
/// Decode is sequential (AVAssetReader), sampling one frame roughly every
/// `sampleEveryMs` by presentation time — the counterpart to Android's
/// MediaExtractor+MediaCodec pass. `grabFrames` uses AVAssetImageGenerator, which
/// is orientation-correct like Android's MediaMetadataRetriever path.
public class PoseLandmarkerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let landmarkCount = 33

  private var eventSink: FlutterEventSink?
  private let workQueue = DispatchQueue(label: "pose_landmarker.work", qos: .userInitiated)

  // Cancellation flag, guarded so the worker and the channel threads agree.
  private let cancelLock = NSLock()
  private var cancelledFlag = false
  private var cancelled: Bool {
    get { cancelLock.lock(); defer { cancelLock.unlock() }; return cancelledFlag }
    set { cancelLock.lock(); cancelledFlag = newValue; cancelLock.unlock() }
  }

  private struct CancelledError: Error {}

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PoseLandmarkerPlugin()
    let methods = FlutterMethodChannel(
      name: "pose_landmarker/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let progress = FlutterEventChannel(
      name: "pose_landmarker/progress", binaryMessenger: registrar.messenger())
    progress.setStreamHandler(instance)
  }

  // MARK: - Method channel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cancel":
      cancelled = true
      result(nil)
    case "grabFrames":
      guard let args = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String,
            let times = args["timestampsMs"] as? [NSNumber]
      else {
        result(FlutterError(code: "bad_args",
                            message: "videoPath and timestampsMs required", details: nil))
        return
      }
      workQueue.async {
        do {
          let frames = try self.grabFrames(videoPath: videoPath,
                                           timesMs: times.map { $0.int64Value })
          DispatchQueue.main.async { result(frames) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "grab_failed",
                                message: self.describe(error), details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// JPEG bytes for each timestamp (ms), orientation-correct. Missing frames are
  /// omitted, matching the Android contract.
  private func grabFrames(videoPath: String, timesMs: [Int64]) throws -> [FlutterStandardTypedData] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var out: [FlutterStandardTypedData] = []
    out.reserveCapacity(timesMs.count)
    for tMs in timesMs {
      let time = CMTime(value: tMs, timescale: 1000)
      guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
      guard let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { continue }
      out.append(FlutterStandardTypedData(bytes: jpeg))
    }
    return out
  }

  // MARK: - Event channel

  public func onListen(withArguments arguments: Any?,
                       eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard let args = arguments as? [String: Any],
          let videoPath = args["videoPath"] as? String,
          let modelPath = args["modelPath"] as? String
    else {
      return FlutterError(code: "bad_args",
                          message: "videoPath and modelPath are required", details: nil)
    }
    let sampleEveryMs = (args["sampleEveryMs"] as? NSNumber)?.int64Value ?? 33
    eventSink = events
    cancelled = false
    workQueue.async {
      self.runEstimation(videoPath: videoPath, modelPath: modelPath,
                         sampleEveryMs: sampleEveryMs, events: events)
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    cancelled = true
    eventSink = nil
    return nil
  }

  // MARK: - Estimation

  private func runEstimation(videoPath: String, modelPath: String,
                             sampleEveryMs: Int64, events: @escaping FlutterEventSink) {
    let step = sampleEveryMs <= 0 ? 33 : sampleEveryMs
    let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    guard let track = asset.tracks(withMediaType: .video).first else {
      post { events(FlutterError(code: "decode", message: "no video track", details: nil)) }
      return
    }
    let durationMs = Int64(CMTimeGetSeconds(asset.duration) * 1000.0)
    if durationMs <= 0 {
      post { events(FlutterError(code: "decode", message: "could not read clip duration", details: nil)) }
      return
    }
    let totalFrames = Int(durationMs / step) + 1
    let orientation = Self.orientation(for: track.preferredTransform)

    do {
      let landmarker = try Self.buildLandmarker(modelPath: modelPath)
      var frames: [[String: Any]] = []
      frames.reserveCapacity(totalFrames)
      var index = 0

      try decodeStreaming(asset: asset, track: track, stepMs: step) { pixelBuffer, tMs in
        if self.cancelled { throw CancelledError() }
        let image = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation)
        let result = try landmarker.detect(videoFrame: image,
                                           timestampInMilliseconds: Int(tMs))
        frames.append(Self.frameToMap(index: index, timestampMs: Double(tMs), result: result))
        if index % 15 == 0 {
          let processed = index
          self.post {
            events(["framesProcessed": processed, "totalFrames": totalFrames])
          }
        }
        index += 1
      }

      post {
        events([
          "framesProcessed": frames.count,
          "totalFrames": totalFrames,
          "frames": frames,
        ])
        events(FlutterEndOfStreamEvent())
      }
    } catch is CancelledError {
      post { events(FlutterEndOfStreamEvent()) }
    } catch {
      post { events(FlutterError(code: "estimation_failed",
                                 message: self.describe(error), details: nil)) }
    }
  }

  /// Sequential decode via AVAssetReader, sampling by presentation time — the
  /// counterpart to the Android MediaCodec loop. Calls [onFrame] with each
  /// sampled frame's pixel buffer and its timestamp in ms.
  private func decodeStreaming(asset: AVAsset, track: AVAssetTrack, stepMs: Int64,
                               onFrame: (CVPixelBuffer, Int64) throws -> Void) throws {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw NSError(domain: "pose_landmarker", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "cannot read video track"])
    }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? NSError(domain: "pose_landmarker", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "reader failed to start"])
    }

    let stepUs = stepMs * 1000
    var nextSampleUs: Int64 = 0
    while reader.status == .reading {
      if cancelled { throw CancelledError() }
      guard let sample = output.copyNextSampleBuffer() else { break }
      let ptsUs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 1_000_000.0)
      if ptsUs >= nextSampleUs, let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
        try onFrame(pixelBuffer, ptsUs / 1000)
        nextSampleUs = (ptsUs / stepUs + 1) * stepUs
      }
    }
    if reader.status == .failed { throw reader.error ?? CancelledError() }
  }

  // MARK: - MediaPipe

  private static func buildLandmarker(modelPath: String) throws -> PoseLandmarker {
    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .video
    options.numPoses = 1
    options.minPoseDetectionConfidence = 0.5
    options.minPosePresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5
    return try PoseLandmarker(options: options)
  }

  private static func frameToMap(index: Int, timestampMs: Double,
                                 result: PoseLandmarkerResult) -> [String: Any] {
    var landmarks: [[Double]] = []
    if let pose = result.landmarks.first {
      landmarks.reserveCapacity(pose.count)
      for lm in pose {
        landmarks.append([
          Double(lm.x), Double(lm.y), Double(lm.z),
          lm.visibility?.doubleValue ?? 0.0,
        ])
      }
    }
    return ["i": index, "t": timestampMs, "lm": landmarks]
  }

  // MARK: - Helpers

  /// The upright orientation to hand MediaPipe, from a track's preferred
  /// transform — the same rotation the video player applies.
  private static func orientation(for transform: CGAffineTransform) -> UIImage.Orientation {
    let angle = atan2(transform.b, transform.a)
    let degrees = Int((angle * 180 / .pi).rounded())
    switch ((degrees % 360) + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  private func post(_ block: @escaping () -> Void) {
    DispatchQueue.main.async(execute: block)
  }

  /// One-line rendering of an error and its underlying causes — enough to
  /// identify a device-only failure from a screenshot, no console needed.
  private func describe(_ error: Error) -> String {
    let ns = error as NSError
    var parts = ["\(type(of: error)): \(ns.localizedDescription)"]
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
      parts.append("← caused by: \(underlying.domain)#\(underlying.code): \(underlying.localizedDescription)")
    }
    return parts.joined(separator: "  ")
  }
}
