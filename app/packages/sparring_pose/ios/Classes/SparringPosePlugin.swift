import AVFoundation
import Flutter
import MediaPipeTasksVision
import UIKit

/// Sparring mode's pose extractor — the iOS twin of the Android
/// `SparringPosePlugin`. Same channels and message shapes: every detected body
/// per sampled frame, with landmarks and an appearance descriptor, streamed back
/// in batches.
///
/// Separate from the `pose_landmarker` plugin on purpose (the single-person
/// pipeline stays untouched); the AVAssetReader decode loop is a copy of that
/// plugin's.
public class SparringPosePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let landmarkCount = 33
  private static let appearanceBins = 11
  private static let minVisibility: Float = 0.3
  private static let maxSamples = 600.0
  private static let batchSize = 20

  private let workQueue = DispatchQueue(label: "sparring_pose.work", qos: .userInitiated)

  private let cancelLock = NSLock()
  private var cancelledFlag = false
  private var cancelled: Bool {
    get { cancelLock.lock(); defer { cancelLock.unlock() }; return cancelledFlag }
    set { cancelLock.lock(); cancelledFlag = newValue; cancelLock.unlock() }
  }

  private struct CancelledError: Error {}

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SparringPosePlugin()
    let methods = FlutterMethodChannel(
      name: "sparring_pose/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let progress = FlutterEventChannel(
      name: "sparring_pose/progress", binaryMessenger: registrar.messenger())
    progress.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cancel":
      cancelled = true
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?,
                       eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard let args = arguments as? [String: Any],
          let videoPath = args["videoPath"] as? String,
          let modelPath = args["modelPath"] as? String
    else {
      return FlutterError(code: "bad_args",
                          message: "videoPath and modelPath are required", details: nil)
    }
    let sampleEveryMs = (args["sampleEveryMs"] as? NSNumber)?.int64Value ?? 50
    let maxPoses = min(max((args["maxPoses"] as? NSNumber)?.intValue ?? 3, 1), 4)
    cancelled = false
    workQueue.async {
      self.runExtraction(videoPath: videoPath, modelPath: modelPath,
                         sampleEveryMs: sampleEveryMs, maxPoses: maxPoses, events: events)
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    cancelled = true
    return nil
  }

  // MARK: - Extraction

  private func runExtraction(videoPath: String, modelPath: String, sampleEveryMs: Int64,
                             maxPoses: Int, events: @escaping FlutterEventSink) {
    let step = sampleEveryMs <= 0 ? 50 : sampleEveryMs
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
      let landmarker = try Self.buildLandmarker(modelPath: modelPath, maxPoses: maxPoses)
      var batch: [[String: Any]] = []
      var index = 0

      try decodeStreaming(asset: asset, track: track, stepMs: step) { pixelBuffer, tMs in
        if self.cancelled { throw CancelledError() }
        let image = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation)
        let result = try landmarker.detect(videoFrame: image,
                                           timestampInMilliseconds: Int(tMs))
        var poses: [[String: Any]] = []
        for pose in result.landmarks {
          poses.append([
            "lm": Self.landmarksData(pose),
            "app": Self.appearance(pixelBuffer: pixelBuffer, orientation: orientation,
                                   pose: pose),
          ])
        }
        batch.append(["i": index, "t": Double(tMs), "poses": poses])
        index += 1
        if batch.count >= Self.batchSize {
          let toSend = batch
          let done = index
          batch = []
          self.post {
            events(["framesProcessed": done, "totalFrames": totalFrames, "frames": toSend])
          }
        }
      }

      let rest = batch
      let done = index
      post {
        if !rest.isEmpty {
          events(["framesProcessed": done, "totalFrames": totalFrames, "frames": rest])
        }
        events(["framesProcessed": done, "totalFrames": totalFrames, "done": true])
        events(FlutterEndOfStreamEvent)
      }
    } catch is CancelledError {
      post { events(FlutterEndOfStreamEvent) }
    } catch {
      post { events(FlutterError(code: "extraction_failed",
                                 message: self.describe(error), details: nil)) }
    }
  }

  private func decodeStreaming(asset: AVAsset, track: AVAssetTrack, stepMs: Int64,
                               onFrame: (CVPixelBuffer, Int64) throws -> Void) throws {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw NSError(domain: "sparring_pose", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "cannot read video track"])
    }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? NSError(domain: "sparring_pose", code: 2,
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

  private static func buildLandmarker(modelPath: String, maxPoses: Int) throws -> PoseLandmarker {
    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .video
    options.numPoses = maxPoses
    options.minPoseDetectionConfidence = 0.5
    options.minPosePresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5
    return try PoseLandmarker(options: options)
  }

  private static func landmarksData(_ pose: [NormalizedLandmark]) -> FlutterStandardTypedData {
    var values = [Float](repeating: 0, count: landmarkCount * 4)
    for k in 0..<min(pose.count, landmarkCount) {
      let lm = pose[k]
      values[k * 4] = lm.x
      values[k * 4 + 1] = lm.y
      values[k * 4 + 2] = lm.z
      values[k * 4 + 3] = lm.visibility?.floatValue ?? 0
    }
    return float32Data(values)
  }

  private static func float32Data(_ values: [Float]) -> FlutterStandardTypedData {
    let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
    return FlutterStandardTypedData(float32: data)
  }

  // MARK: - Appearance (mirrors the Android plugin exactly)

  private static func appearance(pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation,
                                 pose: [NormalizedLandmark]) -> FlutterStandardTypedData {
    var out = [Float](repeating: 0, count: appearanceBins * 2)
    guard pose.count >= landmarkCount else { return float32Data(out) }
    func vis(_ i: Int) -> Float { pose[i].visibility?.floatValue ?? 0 }
    func x(_ i: Int) -> Float { pose[i].x }
    func y(_ i: Int) -> Float { pose[i].y }

    guard vis(11) >= minVisibility, vis(12) >= minVisibility,
          vis(23) >= minVisibility, vis(24) >= minVisibility
    else { return float32Data(out) }
    let top = min(y(11), y(12))
    let bottom = max(y(23), y(24))
    let torsoH = bottom - top
    guard torsoH > 0 else { return float32Data(out) }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let cx = (x(11) + x(12) + x(23) + x(24)) / 4
    let spanX = max(max(x(11), x(12)), max(x(23), x(24))) - min(min(x(11), x(12)), min(x(23), x(24)))
    let torsoW = max(spanX, 0.5 * torsoH)
    histogram(pixelBuffer, orientation,
              cx - 0.35 * torsoW, top + 0.15 * torsoH,
              cx + 0.35 * torsoW, bottom - 0.1 * torsoH,
              &out, 0)

    let hipY = (y(23) + y(24)) / 2
    let hipX = (x(23) + x(24)) / 2
    let kneesOk = vis(25) >= minVisibility && vis(26) >= minVisibility
    let seg = kneesOk ? ((y(25) + y(26)) / 2 - hipY) : 0.4 * torsoH
    let shortsH = seg > 0 ? 0.5 * seg : 0.2 * torsoH
    let shortsW = max(abs(x(23) - x(24)), 0.35 * torsoH)
    histogram(pixelBuffer, orientation,
              hipX - 0.5 * shortsW, hipY,
              hipX + 0.5 * shortsW, hipY + shortsH,
              &out, appearanceBins)
    return float32Data(out)
  }

  /// Fills one histogram from an upright-normalised box. The pixel buffer is in
  /// sensor orientation, so each sample point is mapped back through
  /// [orientation] first. Assumes the base address is locked.
  private static func histogram(_ buffer: CVPixelBuffer, _ orientation: UIImage.Orientation,
                                _ nx0: Float, _ ny0: Float, _ nx1: Float, _ ny1: Float,
                                _ out: inout [Float], _ offset: Int) {
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let pixels = base.assumingMemoryBound(to: UInt8.self)

    // Upright image size, for the sampling stride.
    let rotated = orientation == .left || orientation == .right
    let uprightW = Float(rotated ? height : width)
    let uprightH = Float(rotated ? width : height)
    let x0 = max(0, min(1, nx0)), x1 = max(0, min(1, nx1))
    let y0 = max(0, min(1, ny0)), y1 = max(0, min(1, ny1))
    let regionW = (x1 - x0) * uprightW
    let regionH = (y1 - y0) * uprightH
    guard regionW >= 2, regionH >= 2 else { return }
    let stride = max(1.0, (Double(regionW * regionH) / maxSamples).squareRoot())
    let du = Float(stride) / uprightW
    let dv = Float(stride) / uprightH

    var count: Float = 0
    var v = y0
    while v < y1 {
      var u = x0
      while u < x1 {
        // Upright (u, v) → raw sensor-orientation (rx, ry), normalised.
        let raw: (Float, Float)
        switch orientation {
        case .right: raw = (v, 1 - u)
        case .left: raw = (1 - v, u)
        case .down: raw = (1 - u, 1 - v)
        default: raw = (u, v)
        }
        let px = min(width - 1, max(0, Int(raw.0 * Float(width))))
        let py = min(height - 1, max(0, Int(raw.1 * Float(height))))
        let p = pixels + py * rowBytes + px * 4 // BGRA
        out[offset + colourBin(Int(p[2]), Int(p[1]), Int(p[0]))] += 1
        count += 1
        u += du
      }
      v += dv
    }
    guard count > 0 else { return }
    for k in 0..<appearanceBins { out[offset + k] /= count }
  }

  private static func colourBin(_ r: Int, _ g: Int, _ b: Int) -> Int {
    let mx = max(r, max(g, b))
    let mn = min(r, min(g, b))
    let v = Float(mx) / 255
    let s: Float = mx == 0 ? 0 : Float(mx - mn) / Float(mx)
    if v < 0.2 { return 8 }
    if s < 0.25 { return v < 0.7 ? 9 : 10 }
    let d = Float(mx - mn)
    var hue: Float
    if mx == r {
      hue = 60 * (Float(g - b) / d).truncatingRemainder(dividingBy: 6)
    } else if mx == g {
      hue = 60 * (Float(b - r) / d + 2)
    } else {
      hue = 60 * (Float(r - g) / d + 4)
    }
    if hue < 0 { hue += 360 }
    return min(7, Int(hue / 45))
  }

  // MARK: - Helpers

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

  private func describe(_ error: Error) -> String {
    let ns = error as NSError
    var parts = ["\(type(of: error)): \(ns.localizedDescription)"]
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
      parts.append("← caused by: \(underlying.domain)#\(underlying.code): \(underlying.localizedDescription)")
    }
    return parts.joined(separator: "  ")
  }
}
