import Foundation

/// Orchestrates input capture → LLM extraction → UI presentation
@MainActor
final class InputCoordinator {
    private let router = LLMRouter()
    private let screenCapture = ScreenCaptureManager()
    private let selectedTextReader = SelectedTextReader()

    // MARK: - Busy Guard

    /// 처리 중이거나 폼이 열려 있으면 새 추출 차단
    private func guardBusy(state: AppState) -> Bool {
        if state.isProcessing {
            Log.debug("[Input] Blocked: already processing")
            return true
        }
        if state.showScheduleForm {
            Log.debug("[Input] Blocked: form is open")
            return true
        }
        return false
    }

    // MARK: - Invocation Method 1: Clipboard

    /// Process clipboard content (text or image)
    func processClipboard(state: AppState) async {
        guard !guardBusy(state: state) else { return }
        let content = ClipboardReader.read()

        switch content {
        case .text(let text):
            Log.input.info("Clipboard text: \(text.count) chars")
            await extractFromText(text, state: state)

        case .image(let data):
            Log.input.info("Clipboard image: \(data.count) bytes")
            await extractFromImage(data, state: state)

        case .empty:
            state.lastError = String(localized: "클립보드가 비어있습니다.", comment: "Input error")
            state.showError = true
        }
    }

    // MARK: - Invocation Method 2: Screen Capture

    /// Capture screen region and extract schedule from image
    func processScreenCapture(state: AppState) async {
        guard !guardBusy(state: state) else { return }
        Log.input.info("Starting screen capture...")

        guard let imageData = await screenCapture.captureRegion() else {
            Log.input.info("Screen capture cancelled")
            return  // User cancelled, no error
        }

        await extractFromImage(imageData, state: state)
    }

    // MARK: - Invocation Method 3: Selected Text

    /// Read selected text from frontmost app and extract schedule
    func processSelectedText(state: AppState) async {
        guard !guardBusy(state: state) else { return }
        Log.input.info("Reading selected text...")

        guard let text = await selectedTextReader.readSelectedText() else {
            state.lastError = String(localized: "선택된 텍스트를 읽을 수 없습니다.", comment: "Input error")
            state.showError = true
            return
        }

        await extractFromText(text, state: state)
    }

    // MARK: - Input Limits

    private static let maxTextLength = 5_000           // 5K chars
    private static let maxImageSize = 10_000_000     // 10MB

    // MARK: - LLM Extraction

    /// Extract schedule from text
    func extractFromText(_ text: String, state: AppState) async {
        guard text.count <= Self.maxTextLength else {
            state.lastError = String(localized: "텍스트가 너무 깁니다 (최대 5,000자).", comment: "Input too long")
            state.showError = true
            return
        }

        state.isProcessing = true
        state.lastError = nil
        state.lastInputText = text

        do {
            let event = try await router.extract(
                from: text,
                providerID: state.selectedProvider,
                model: state.selectedModel
            )
            state.extractedEvent = event
            state.showScheduleForm = true
        } catch LLMError.noScheduleFound {
            // Fallback: LLM이 일정을 못 찾았지만 날짜 패턴이 있으면 종일 일정으로 생성
            if let fallback = Self.fallbackAllDayEvent(from: text) {
                state.extractedEvent = fallback
                state.showScheduleForm = true
            } else {
                handleError(LLMError.noScheduleFound, state: state)
            }
        } catch {
            handleError(error, state: state)
        }

        state.isProcessing = false
    }

    /// 짧은 텍스트에서 날짜 패턴을 찾아 종일 일정으로 폴백
    private static func fallbackAllDayEvent(from text: String) -> ScheduleEvent? {
        let year = Calendar.current.component(.year, from: Date())

        // "N월 N일" 패턴 매칭
        let pattern = #"(\d{1,2})\s*월\s*(\d{1,2})\s*일"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let mRange = Range(match.range(at: 1), in: text),
              let dRange = Range(match.range(at: 2), in: text),
              let month = Int(text[mRange]),
              let day = Int(text[dRange]),
              month >= 1, month <= 12, day >= 1, day <= 31
        else { return nil }

        let dateStr = String(format: "%04d-%02d-%02d", year, month, day)

        // 날짜 부분을 제거하고 남은 텍스트를 제목으로
        var title = text
            .replacingOccurrences(of: #"\d{1,2}\s*월\s*\d{1,2}\s*일"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = "일정" }

        Log.debug("[Fallback] Created all-day event: \(title) on \(dateStr)")

        return ScheduleEvent(
            title: title,
            startDate: dateStr,
            startTime: nil,
            endDate: dateStr,
            endTime: nil,
            allDay: true,
            location: nil,
            notes: nil,
            error: nil
        )
    }

    /// Extract schedule from image via OCR → text pipeline
    /// All providers receive text only — image never leaves the device.
    func extractFromImage(_ imageData: Data, state: AppState) async {
        guard imageData.count <= Self.maxImageSize else {
            state.lastError = String(localized: "이미지가 너무 큽니다 (최대 10MB).", comment: "Image too large")
            state.showError = true
            return
        }

        state.isProcessing = true
        state.lastError = nil

        do {
            // Step 1: Local Vision OCR (image stays on device)
            let ocrStart = Date()
            let ocrText = try await OCRReader.recognizeText(from: imageData)
            let ocrElapsed = Date().timeIntervalSince(ocrStart)
            Log.debug("[OCR] Completed in \(String(format: "%.1f", ocrElapsed))s — \(ocrText.count) chars")

            guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.noScheduleFound
            }

            // Step 2: Send OCR text to LLM (same as text extraction)
            let prefixed = "[이미지에서 추출된 텍스트]\n\(ocrText)"
            state.lastInputText = prefixed
            let event = try await router.extract(
                from: prefixed,
                providerID: state.selectedProvider,
                model: state.selectedModel
            )
            state.extractedEvent = event
            state.showScheduleForm = true
        } catch {
            handleError(error, state: state)
        }

        state.isProcessing = false
    }

    // MARK: - Re-analysis

    /// 다른 프로바이더로 재추출 (폼에서 호출)
    func reanalyze(text: String, providerID: LLMProviderID) async throws -> ScheduleEvent {
        let model = providerID.defaultModels[0]
        Log.llm.info("Re-analyzing with \(providerID.displayName) / \(model.id)")
        return try await router.extract(from: text, providerID: providerID, model: model)
    }

    // MARK: - Private

    private func handleError(_ error: Error, state: AppState) {
        Log.input.error("Extraction failed: \(error.localizedDescription)")
        state.lastError = error.localizedDescription
        state.showError = true
    }
}
