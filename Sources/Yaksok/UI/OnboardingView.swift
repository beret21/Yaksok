import SwiftUI

/// First-run onboarding — single page setup
struct OnboardingView: View {
    var onDismiss: () -> Void

    @State private var apiKey: String = ""
    @State private var selectedProvider: LLMProviderID = .gemini
    @State private var apiKeySaved = false
    private let accentOrange = Color(red: 0.95, green: 0.45, blue: 0.25)

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                    .foregroundColor(accentOrange)

                Text("Yaksok에 오신 것을 환영합니다!", comment: "Onboarding title")
                    .font(.title2.weight(.bold))

                Text("텍스트/이미지에서 일정을 추출하여 캘린더에 등록합니다.", comment: "Onboarding subtitle")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Apple Intelligence — default, ready to go
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.intelligence")
                        .font(.title3)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence (기본)", comment: "Default provider")
                            .font(.callout.weight(.medium))
                        Text("API 키 없이 바로 사용 가능합니다.", comment: "No API key needed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("추출 품질이 만족스럽지 않으면 설정에서 Gemini, OpenAI, Claude로 변경할 수 있습니다.", comment: "Quality note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Optional: external LLM API key
            DisclosureGroup(String(localized: "외부 LLM 서비스 설정 (선택사항)", comment: "Optional API setup")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(String(localized: "서비스", comment: "Provider picker"),
                           selection: $selectedProvider) {
                        ForEach(LLMProviderID.allCases.filter { $0 != .apple }) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .padding(.top, 4)

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(String(localized: "저장", comment: "Save API key")) {
                            saveAPIKeyIfNeeded()
                            withAnimation { apiKeySaved = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { apiKeySaved = false }
                            }
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                        if apiKeySaved {
                            Label(String(localized: "저장됨", comment: "Saved"), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                            Text(apiKeyHelpText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .font(.callout)

            Divider()

            // Shortcuts
            VStack(alignment: .leading, spacing: 6) {
                Text("기본 단축키:", comment: "Default shortcuts")
                    .font(.callout.weight(.medium))
                HStack {
                    shortcutRow("⌘⇧E", String(localized: "클립보드에서 추출", comment: "Clipboard shortcut"))
                    Spacer()
                    shortcutRow("⌘⇧D", String(localized: "선택 텍스트 추출", comment: "Selection shortcut"))
                }
            }

            Spacer()

            // Start button
            HStack {
                Spacer()
                Button(String(localized: "시작하기", comment: "Start button")) {
                    saveAPIKeyIfNeeded()
                    markOnboardingDone()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentOrange)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 440, height: 520)
    }

    // MARK: - Helpers

    private var apiKeyHelpText: String {
        switch selectedProvider {
        case .gemini: String(localized: "Google AI Studio에서 발급 (aistudio.google.com)", comment: "Gemini help")
        case .openai: String(localized: "OpenAI Platform에서 발급 (platform.openai.com)", comment: "OpenAI help")
        case .claude: String(localized: "Anthropic Console에서 발급 (console.anthropic.com)", comment: "Claude help")
        case .apple: ""
        }
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
            Text(desc)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private func saveAPIKeyIfNeeded() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? KeychainManager.save(key: selectedProvider.keychainKey, value: trimmed)
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider")
        UserDefaults.standard.set(selectedProvider.defaultModels[0].id, forKey: "selectedModelID")
    }

    // MARK: - Onboarding state

    private static let onboardingDoneKey = "onboardingDone"

    static var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: onboardingDoneKey)
    }

    private func markOnboardingDone() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
    }
}
