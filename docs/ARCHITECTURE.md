# Yaksok 아키텍처 설계도

## 1. 시스템 개요

```
텍스트/이미지 입력 → LLM 추출 → 일정 편집 폼 → Apple Calendar 등록
```

- **앱 유형**: macOS 메뉴바 앱 (LSUIElement, 도크 아이콘 없음)
- **번들 ID**: com.beret21.yaksok
- **플랫폼**: macOS 26+ (Swift 6.2, SPM)
- **총 코드**: ~5,100줄, 33개 Swift 파일

---

## 2. 모듈 구조

```
Yaksok/
├── App/            ← 앱 진입점, 상태 관리, Shortcuts 연동
├── Calendar/       ← EventKit 래퍼, 일정 모델
├── Input/          ← 7가지 입력 방식 처리
├── LLM/            ← 4개 프로바이더 추상화, 프롬프트, 라우터
├── UI/             ← SwiftUI 뷰 (폼, 설정, 온보딩, 타임라인)
├── Security/       ← Keychain API 키 관리
└── Utilities/      ← 로그, OCR, 이미지 변환
```

---

## 3. 데이터 흐름도

```
┌─────────────────── 입력 (7가지) ───────────────────┐
│                                                      │
│  1. 클립보드 (⌘⇧E)     5. Services 메뉴            │
│  2. 화면 캡처 (⌘⇧⌥S)   6. Shortcuts.app            │
│  3. 선택 텍스트 (⌘⇧D)   7. URL Scheme               │
│  4. 드래그앤드롭                                     │
│                                                      │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │ InputCoordinator │  ← 중앙 오케스트레이터
              │  - 입력 크기 검증  │     텍스트 5K자, 이미지 10MB
              │  - 이미지→OCR     │     Vision 프레임워크 (로컬)
              │  - 중복 추출 차단  │     isProcessing 가드
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │    LLMRouter     │  ← 프로바이더 선택/라우팅
              │                  │
              ├─ AppleProvider   │  FoundationModels (로컬, macOS 26+)
              ├─ GeminiProvider  │  REST API (x-goog-api-key 헤더)
              ├─ OpenAIProvider  │  REST API (Bearer 토큰)
              └─ ClaudeProvider  │  REST API (x-api-key 헤더)
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  ScheduleEvent   │  ← JSON 파싱 (3단계 폴백)
              │  (Codable 모델)  │     JSONDecoder → 배열 → JSONSerialization
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ ScheduleFormView │  ← SwiftUI 편집 폼
              │  - 제목/날짜/시간  │
              │  - 장소/메모       │
              │  - 캘린더 선택     │
              │  - 충돌 타임라인   │
              │  - 재분석 버튼     │
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ CalendarManager  │  ← EventKit 래퍼
              │  - 권한 요청      │     requestFullAccessToEvents()
              │  - 이벤트 생성    │     EKEvent → store.save()
              │  - 충돌 조회      │     predicateForEvents()
              └──────────────────┘
```

---

## 4. 모듈 상세

### 4.1 App 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| YaksokApp.swift | 380 | @main 진입점, NSStatusItem, 메뉴, 전역 단축키, URL Scheme, Services |
| AppState.swift | 246 | @Observable 중앙 상태 (프로바이더, 모델, 히스토리, 처리 상태) |
| AppIntents.swift | 87 | Shortcuts.app 연동 (3개 인텐트) |

**YaksokApp 핵심 흐름:**
```
applicationDidFinishLaunching
  → setupEditMenu()          // Cmd+C/V/X/A 지원 (LSUIElement 앱용)
  → setupStatusItem()        // NSStatusItem + NSMenu + 드래그앤드롭
  → setupGlobalHotkeys()     // Carbon RegisterEventHotKey
  → registerURLHandler()     // yaksok:// AppleEvent
  → NSRegisterServicesProvider()
  → refreshModels()          // 주 1회 모델 목록 갱신
  → showOnboarding()         // 최초 실행 시
```

**AppState 상태 목록:**
```
selectedProvider: LLMProviderID      ← UserDefaults 저장
selectedModelID: String              ← UserDefaults 저장
selectedModel: LLMModel              ← computed
fetchedModels: [LLMProviderID: [LLMModel]]  ← API에서 가져온 모델 목록
recentHistory: [HistoryItem]         ← 최대 100건, 90일 보관
conflictCheckCalendarIDs: Set<String>
defaultDurationMinutes: Int          ← 15/30/60/90/120
isProcessing: Bool
showScheduleForm: Bool
showError: Bool
extractedEvent: ScheduleEvent?
lastError: String?
lastInputText: String?               ← 재분석용 원본 텍스트
```

### 4.2 Calendar 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| CalendarManager.swift | 147 | @Observable EventKit 래퍼 |
| ScheduleEvent.swift | 127 | LLM 응답 → Codable 모델 → Date 파싱 |

**CalendarManager 상태 머신:**
```
초기 상태: accessGranted=false, authorizationChecked=false

requestAccess() 호출
  → macOS 14+: store.requestFullAccessToEvents()
  → 이전: store.requestAccess(to: .event)

  성공 → accessGranted=true, authorizationChecked=true, loadCalendars()
  실패 → accessGranted=false, authorizationChecked=true, errorMessage 설정
```

**ScheduleEvent JSON 스키마:**
```json
{
  "title": "회의",
  "start_date": "2026-04-03",
  "start_time": "14:00",
  "end_date": "2026-04-03",
  "end_time": "15:00",
  "all_day": false,
  "location": "회의실 A",
  "notes": "발표 자료 준비"
}
```

**JSON 파싱 3단계 폴백:**
```
1. JSONDecoder.decode(ScheduleEvent.self, from: data)
2. 배열인 경우 첫 번째 요소 추출
3. JSONSerialization → 수동 키 매핑
```

### 4.3 Input 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| InputCoordinator.swift | 214 | 중앙 오케스트레이터, 폴백 로직 |
| ClipboardReader.swift | 93 | NSPasteboard 읽기 (텍스트/이미지/URL) |
| ScreenCaptureManager.swift | 56 | screencapture -i -x 명령 실행 |
| SelectedTextReader.swift | 70 | AXUIElement + Cmd+C 폴백 |
| HotkeyManager.swift | 208 | Carbon 전역 단축키 등록 |
| DragDropHandler.swift | 130 | NSDraggingDestination 구현 |

**입력 처리 파이프라인:**
```
모든 이미지 입력:
  이미지 → Vision OCR (로컬) → 텍스트 → LLM
  ※ 이미지는 절대 외부 API로 전송하지 않음 (프라이버시)

텍스트 입력:
  텍스트 → LLM 직접 전달

폴백:
  LLM 실패 + "N월 N일" 패턴 매칭 → 종일 일정 자동 생성
```

**ClipboardReader 우선순위:**
```
1. 직접 이미지 (TIFF/PNG in pasteboard)
2. 파일 URL 이미지 (유니버셜 클립보드, iPhone→Mac)
3. 텍스트
4. 비어있음
```

### 4.4 LLM 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| LLMProvider.swift | 80 | protocol + 모델 정의 + 프로바이더 ID |
| LLMRouter.swift | 35 | 프로바이더 선택/라우팅 |
| LLMError.swift | 49 | 에러 enum (한국어 메시지) |
| SchedulePrompt.swift | 281 | 시스템 프롬프트 생성 (한/영) |
| ModelFetcher.swift | 125 | API에서 모델 목록 가져오기 |
| Providers/AppleProvider.swift | 64 | FoundationModels (로컬) |
| Providers/GeminiProvider.swift | 131 | REST API |
| Providers/OpenAIProvider.swift | 105 | REST API |
| Providers/ClaudeProvider.swift | 119 | REST API |

**프로바이더 비교:**

| | Apple | Gemini | OpenAI | Claude |
|---|---|---|---|---|
| API | FoundationModels | REST | REST | REST |
| 인증 | 없음 | x-goog-api-key 헤더 | Bearer 토큰 | x-api-key 헤더 |
| 타임아웃 | - | 60초 | 30초 | 30초 |
| 이미지 | OCR→텍스트 | OCR→텍스트 | OCR→텍스트 | OCR→텍스트 |
| 기본 모델 | apple-intelligence | gemini-2.0-flash | gpt-4o-mini | claude-sonnet-4 |
| URLSession | - | ephemeral | ephemeral | ephemeral |

**LLMError 케이스:**
```
noAPIKey              → "API 키가 설정되지 않았습니다..."
authenticationFailed  → "API 키 인증에 실패했습니다..."
rateLimitExceeded     → "API 요청 한도를 초과했습니다..."
networkError          → "네트워크 오류..."
serverError           → "서버 오류 (코드): 메시지"
invalidResponse       → "LLM 응답을 파싱할 수 없습니다..."
noScheduleFound       → "일정 정보를 찾을 수 없습니다..."
appleIntelligenceError → "Apple Intelligence를 사용할 수 없습니다..."
unsupportedModel, imageEncodingFailed, timeout
```

**프롬프트 구조 (SchedulePrompt.korean(), ~2,500자):**
```
1. 현재 시간 컨텍스트 (오늘, 내일, 모레, 이번주 금요일...)
2. 핵심 규칙 (end_date >= start_date, 종료시간 기본값 등)
3. 날짜/시간 파싱 규칙 (상대 날짜, 시간 변환)
4. 일정 유형별 처리 (세미나, 회의, 부고, 승차권, 온라인 미팅)
5. 출력 형식 (JSON 스키마)
```

### 4.5 UI 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| ScheduleFormView.swift | 772 | 일정 편집 폼 (메인 UI) |
| ScheduleFormWindow.swift | 46 | NSWindow 라이프사이클 관리 |
| SettingsView.swift | 509 | 설정 (5개 탭) |
| StatusMenuBuilder.swift | 136 | NSMenu 구성 |
| OnboardingView.swift | 340 | 초기 설정 (2페이지) |
| ProcessingStatusView.swift | 31 | NSPopover 진행 상태 |
| DayTimelineView.swift | 239 | 일정 충돌 타임라인 |
| KeyRecorderView.swift | 99 | 단축키 입력 캡처 |

**ScheduleFormView 레이아웃:**
```
┌─────────────────────────────────────────────────┐
│ [v1.0.6 · Apple Intelligence · apple-intelligence] │
├────────────────────────────┬────────────────────┤
│ 제목: [____________]       │                    │
│                            │  DayTimelineView   │
│ 종일: □                    │  (충돌 표시)        │
│ 시작: [날짜] [시간]         │                    │
│ 종료: [날짜] [시간]         │  ■ 기존 일정 (그레이)│
│                            │  ■ 신규 일정 (그린)  │
│ 장소: [____________]       │  ■ 충돌 (레드)      │
│ 메모: [____________]       │                    │
│                            │                    │
│ 캘린더: [▼ 선택]            │                    │
├────────────────────────────┴────────────────────┤
│ [취소]  [재분석 ▼]                    [등록] │
└─────────────────────────────────────────────────┘
   520px (폼) + 130px (타임라인) = 650px
```

**캘린더 권한 처리 (ScheduleFormView):**
```
.onAppear → calendarManager.requestAccess()
  → 성공: 캘린더 목록 로드, 폼 표시
  → 실패: permissionDeniedView 표시 (시스템 설정 열기 버튼)
```

### 4.6 Security 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| KeychainManager.swift | 118 | SecItem API 래퍼 + 레거시 마이그레이션 |

**Keychain 키 이름:**
```
apiKey_gemini   → Gemini API 키
apiKey_openai   → OpenAI API 키
apiKey_claude   → Claude API 키
```

**보안 정책:**
- kSecAttrAccessible: .whenUnlocked
- kSecAttrSynchronizable: false (iCloud 동기화 금지)
- 레거시 ~/.yaksok/ 파일 → Keychain 자동 마이그레이션 후 삭제

### 4.7 Utilities 모듈

| 파일 | 줄수 | 역할 |
|------|------|------|
| Logger.swift | 43 | os.Logger + 파일 로그 |
| OCRReader.swift | 58 | Vision 프레임워크 OCR |
| ImageConverter.swift | 27 | NSImage → JPEG 변환 |

**OCR 설정:**
- Recognition level: .accurate
- 언어: ko-KR, en-US, de-DE, ja-JP
- usesLanguageCorrection: true

---

## 5. 외부 의존성

| 프레임워크 | 용도 | 모듈 |
|-----------|------|------|
| AppKit | NSStatusItem, NSMenu, NSWindow, NSPasteboard | App, Input, UI |
| SwiftUI | 모든 뷰 | UI |
| EventKit | EKEventStore, EKEvent, EKCalendar | Calendar |
| FoundationModels | LanguageModelSession (macOS 26+) | LLM/Apple |
| Vision | VNRecognizeTextRequest (OCR) | Utilities |
| Security | SecItemAdd/SecItemCopyMatching | Security |
| Sparkle 2.x | SPUStandardUpdaterController | App |
| Carbon | RegisterEventHotKey | Input |
| ServiceManagement | SMAppService (로그인 시 자동 시작) | UI/Settings |
| ApplicationServices | AXUIElement (접근성) | Input |
| AppIntents | AppIntent, AppShortcutsProvider | App |

---

## 6. 빌드 파이프라인

```
build.sh [--sign] [--zip]

1. swift build -c release
2. swiftc Share Extension (YaksokShare.appex)
3. .app 번들 패키징
   - 바이너리 복사
   - Info.plist 복사
   - AppIcon.icns 복사
   - Share Extension 패키징
4. Sparkle.framework 임베딩 + rpath
5. 코드 서명
   - 기본: ad-hoc (--sign 없이)
   - --sign: Developer ID (DT9JQA4X82)
     → /tmp에서 서명 (Dropbox xattr 우회)
     → inside-out: appex → Sparkle 내부 → Sparkle → 앱
     → 서명 후 xattr -cr (Dropbox 메타데이터 제거)
6. 공증 (--zip)
   - ditto -c -k → notarytool submit → stapler staple
   - Sparkle sign_update → edSignature + length
7. Services 새로고침 (pbs -flush/-update)
```

**릴리즈 절차:**
```
1. Info.plist: CFBundleVersion + CFBundleShortVersionString 업데이트
2. bash build.sh --sign --zip
3. appcast.xml에 edSignature + length 기입
4. gh release create vX.Y.Z Yaksok-X.Y.Z.zip
5. git push (appcast.xml)
```

---

## 7. 권한 체계

| 권한 | 용도 | 요청 시점 | 필수 |
|------|------|----------|------|
| 캘린더 (Full Access) | 일정 등록/조회 | ScheduleFormView.onAppear | **필수** |
| 접근성 | 선택 텍스트 읽기 (⌘⇧D) | 기능 사용 시 | 선택 |
| 화면 기록 | 화면 캡처 (⌘⇧⌥S) | 기능 사용 시 | 선택 |

**캘린더 권한 흐름 (현재):**
```
ScheduleFormView.onAppear
  → calendarManager.requestAccess()
    → EKEventStore.requestFullAccessToEvents()
      → 시스템 다이얼로그 (최초 1회)
      → 허용: loadCalendars() → 폼 표시
      → 거부: permissionDeniedView (시스템 설정 열기 안내)
```

**필수 조건 (3가지 모두 충족해야 함):**
```
1. Info.plist: NSCalendarsFullAccessUsageDescription (권한 요청 메시지)
2. Entitlements: com.apple.security.personal-information.calendars (Hardened Runtime 필수)
3. 코드: EKEventStore.requestFullAccessToEvents() 호출
```
※ Hardened Runtime (--options runtime) 앱은 엔타이틀먼트 없이는
   requestFullAccessToEvents() 호출해도 시스템 다이얼로그가 표시되지 않음.
   Info.plist만으로는 부족함.

---

## 8. 알려진 이슈

| # | 이슈 | 심각도 | 상태 |
|---|------|--------|------|
| 1 | ~~캘린더 권한~~ | - | **해결: 엔타이틀먼트 추가 (v1.1.0)** |
| 2 | Apple Intelligence: macOS 26 미설정 시 NSURLError -1011 | 중간 | v1.0.6 메시지 개선 |
| 3 | NSPopover: Bartender로 아이콘 숨기면 좌측 상단에 표시 | 낮음 | 미해결 |
| 4 | @Generable: instructions 분리 시 ~3B 모델 혼동 | 낮음 | 추가 테스트 필요 |
| 5 | Dropbox xattr: 서명 후 Dropbox가 xattr 재추가 가능 | 중간 | build.sh에서 제거 |

---

## 9. 버전 히스토리

| 버전 | 빌드 | 주요 변경 |
|------|------|----------|
| 1.0.0 | 1 | 최초 릴리즈 — 4개 LLM, 7가지 입력, EventKit, Sparkle |
| 1.0.1 | 2 | 온보딩 개선, Apple 공증 자동화 |
| 1.0.2 | 3 | 메뉴 v/Provider/Model 표시, Claude 모델 API |
| 1.0.3 | 4 | 온보딩 API 키 즉시 저장 |
| 1.0.4 | 5 | CalendarManager store 통합 (임시 EKEventStore 제거) |
| 1.0.5 | 6 | 캘린더 권한: 시스템 설정 직접 열기 |
| 1.0.6 | 7 | 온보딩 캘린더 페이지 제거, Apple Intelligence 에러 개선, 서버 에러 메시지 개선 |
