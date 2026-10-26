import AppKit
import Vision

/// Offline OCR via the system Vision framework (no network, no dependencies).
public final class OCRService {
    public static func recognizeText(
        in image: CGImage,
        completion: @escaping (String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                DispatchQueue.main.async {
                    completion(lines.joined(separator: "\n").nilIfEmpty)
                }
            } catch {
                log("ocr failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

public extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
