import AppKit
import Vision

/// Vision OCR utility — extracts text from images locally (no network)
enum OCRReader {

    /// Perform OCR on image data and return recognized text
    static func recognizeText(from imageData: Data) async throws -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw OCRError.imageDecodeFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US", "de-DE", "ja-JP"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum OCRError: LocalizedError {
        case imageDecodeFailed
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .imageDecodeFailed: return "이미지를 읽을 수 없습니다."
            case .noTextFound: return "이미지에서 텍스트를 찾을 수 없습니다."
            }
        }
    }
}
