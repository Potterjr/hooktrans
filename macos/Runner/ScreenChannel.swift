import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import Vision

/// Method channel "hooktrans/screen":
///  - requestPermission() -> Bool
///  - screenshot() -> {png, width, height, scale}   (main display, points)
///  - captureText({x,y,w,h, languages, force}) -> {changed, text}
///
/// Capture uses ScreenCaptureKit with this app's own windows excluded, so the
/// overlay can sit on top of the game without being read back by OCR.
@available(macOS 14.0, *)
final class ScreenChannel {
  private let channel: FlutterMethodChannel
  private var lastSignature: [UInt8]?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "hooktrans/screen", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "requestPermission":
        let ok = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        result(ok)
      case "screenshot":
        let args = call.arguments as? [String: Any] ?? [:]
        Task { await self.screenshot(args: args, result: result) }
      case "captureText":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "args", message: "missing arguments", details: nil))
          return
        }
        Task { await self.captureText(args: args, result: result) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - helpers

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, _ code: String, _ error: Error) {
    DispatchQueue.main.async {
      result(FlutterError(code: code, message: error.localizedDescription, details: nil))
    }
  }

  /// Picks a display by id, else the one containing [point] (global
  /// top-left-origin coordinates), else the main display.
  private func displayFilter(displayId: UInt32?, point: CGPoint?) async throws -> (SCContentFilter, SCDisplay, CGFloat) {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    var display: SCDisplay? = nil
    if let id = displayId { display = content.displays.first(where: { $0.displayID == id }) }
    if display == nil, let pt = point { display = content.displays.first(where: { $0.frame.contains(pt) }) }
    if display == nil { display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first }
    guard let display = display else {
      throw NSError(domain: "hooktrans", code: 1, userInfo: [NSLocalizedDescriptionKey: "no display"])
    }
    let me = content.applications.filter { $0.processID == getpid() }
    let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
    let screen = NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
    }
    let scale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    return (filter, display, scale)
  }

  private func capture(rect: CGRect?, displayId: UInt32?, point: CGPoint?) async throws -> (CGImage, SCDisplay, CGFloat) {
    let (filter, display, scale) = try await displayFilter(displayId: displayId, point: point)
    let config = SCStreamConfiguration()
    let r = rect ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
    config.sourceRect = r
    config.width = Int(r.width * scale)
    config.height = Int(r.height * scale)
    config.showsCursor = false
    config.captureResolution = .best
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    return (image, display, scale)
  }

  // MARK: - screenshot

  private func screenshot(args: [String: Any], result: @escaping FlutterResult) async {
    var point: CGPoint? = nil
    if let x = args["x"] as? Double, let y = args["y"] as? Double { point = CGPoint(x: x, y: y) }
    do {
      let (image, display, scale) = try await capture(rect: nil, displayId: nil, point: point)
      let rep = NSBitmapImageRep(cgImage: image)
      guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "hooktrans", code: 2, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
      }
      reply(result, [
        "png": FlutterStandardTypedData(bytes: png),
        "displayId": Int(display.displayID),
        "left": display.frame.origin.x,
        "top": display.frame.origin.y,
        "width": display.frame.width,
        "height": display.frame.height,
        "scale": scale,
      ])
    } catch {
      fail(result, "screenshot", error)
    }
  }

  // MARK: - OCR

  /// Cheap 32x8 grayscale thumbnail used to skip OCR when nothing changed.
  private func signature(of image: CGImage) -> [UInt8] {
    let w = 32, h = 8
    var bytes = [UInt8](repeating: 0, count: w * h)
    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
      return bytes
    }
    ctx.interpolationQuality = .low
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return bytes
  }

  private func differs(_ a: [UInt8]?, _ b: [UInt8]) -> Bool {
    guard let a = a, a.count == b.count else { return true }
    var total = 0
    for i in 0..<a.count { total += abs(Int(a[i]) - Int(b[i])) }
    // Average per-pixel change above ~2/255 counts as a new frame.
    return total > a.count * 2
  }

  private func captureText(args: [String: Any], result: @escaping FlutterResult) async {
    guard let x = args["x"] as? Double, let y = args["y"] as? Double,
          let w = args["w"] as? Double, let h = args["h"] as? Double, w > 1, h > 1 else {
      reply(result, FlutterError(code: "args", message: "bad rect", details: nil))
      return
    }
    let languages = args["languages"] as? [String] ?? ["ja", "en"]
    let force = args["force"] as? Bool ?? false
    let displayId = (args["displayId"] as? Int).map { UInt32($0) }
    do {
      let (image, _, _) = try await capture(rect: CGRect(x: x, y: y, width: w, height: h), displayId: displayId, point: nil)
      let sig = signature(of: image)
      if !force && !differs(lastSignature, sig) {
        reply(result, ["changed": false, "text": NSNull()])
        return
      }
      lastSignature = sig

      let text = try await Task.detached(priority: .userInitiated) { () -> String in
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        // Vision uses a bottom-left origin; sort top to bottom, then left to right.
        let sorted = observations.sorted {
          let dy = $1.boundingBox.midY - $0.boundingBox.midY
          if abs(dy) > 0.02 { return dy < 0 }
          return $0.boundingBox.minX < $1.boundingBox.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
      }.value
      reply(result, ["changed": true, "text": text])
    } catch {
      fail(result, "ocr", error)
    }
  }
}
