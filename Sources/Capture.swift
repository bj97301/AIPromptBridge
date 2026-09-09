import AppKit
import ScreenCaptureKit
import Vision
import ImageIO
import Darwin

final class ScreenCapture {
    private func recognize(_ image: CGImage, bounds: CGRect) throws -> [JSON] {
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([recognition])
        return (recognition.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let rect = observation.boundingBox
            return ["text": candidate.string, "confidence": candidate.confidence,
                    "frame": ["x": bounds.minX + rect.minX * bounds.width,
                              "y": bounds.minY + (1 - rect.maxY) * bounds.height,
                              "width": rect.width * bounds.width, "height": rect.height * bounds.height]]
        }
    }

    func ocr(_ request: JSON, reply: @escaping (JSON) -> Void) {
        guard let path = request["image"] as? String, path.hasPrefix("/") else {
            reply(failure("invalid_request", "Supply an absolute image path.")); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                reply(failure("image_error", "Cannot open the supplied image.")); return
            }
            do {
                let text = try recognize(image, bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                reply(["status": "ok", "source": "image_ocr", "pixel_width": image.width, "pixel_height": image.height, "text": text,
                       "note": "Coordinates are pixels in the supplied image. This does not inspect the current screen."])
            } catch { reply(failure("ocr_failed", error.localizedDescription)) }
        }
    }

    func capture(_ request: JSON, reply: @escaping (JSON) -> Void) {
        guard CGPreflightScreenCaptureAccess() else {
            reply(failure("permission_required", "Enable AIPromptBridge in System Settings > Privacy & Security > Screen & System Audio Recording.", extra: ["permission": "screen_recording"])); return
        }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let selected = request["display"] as? UInt32
                let displays = content.displays.filter { selected == nil || $0.displayID == selected }
                guard !displays.isEmpty else { reply(failure("not_found", "No matching display is available.")); return }
                var outputURL: URL?
                if let path = request["output_dir"] as? String {
                    guard path.hasPrefix("/") else { reply(failure("invalid_request", "Output directory must be an absolute path.")); return }
                    // Require a new private directory so existing captures cannot be overwritten.
                    guard mkdir(path, 0o700) == 0 else { reply(failure("output_error", "Choose a new output directory. Its parent must exist.")); return }
                    outputURL = URL(fileURLWithPath: path, isDirectory: true)
                }
                var results: [JSON] = []
                for display in displays {
                    guard (request["deadline"] as? Double ?? 0) > Date().timeIntervalSince1970 else {
                        reply(failure("expired", "Capture exceeded its deadline.", extra: ["displays": results])); return
                    }
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    let bounds = CGDisplayBounds(display.displayID)
                    config.width = CGDisplayPixelsWide(display.displayID)
                    config.height = CGDisplayPixelsHigh(display.displayID)
                    config.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let text = try recognize(image, bounds: bounds)
                    var item: JSON = ["display_id": display.displayID, "pixel_width": image.width, "pixel_height": image.height,
                                      "frame": ["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height], "text": text]
                    if let folder = outputURL {
                        let url = folder.appendingPathComponent("display-\(display.displayID).png")
                        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                            throw NSError(domain: bridgeID, code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot encode screenshot"])
                        }
                        try data.write(to: url, options: .withoutOverwriting)
                        chmod(url.path, 0o600)
                        item["image_path"] = url.path
                    }
                    results.append(item)
                }
                reply(["status": "ok", "source": "screen_capture_ocr", "displays": results,
                       "note": "OCR supplies text and display coordinates, not trusted button identities. It does not grant Accessibility access or enable protected controls."])
            } catch {
                reply(failure("capture_failed", error.localizedDescription))
            }
        }
    }
}
