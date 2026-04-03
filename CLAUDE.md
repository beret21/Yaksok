# Yaksok - 메뉴바 일정 추출 앱

## 개발 필수 절차 (반드시 준수)

### 설계 단계 — 공식 문서 검토 우선

**새로운 기능을 구현하기 전에 반드시 아래 절차를 먼저 수행한다.**

1. **공식 문서 검색**: 사용하려는 Apple 프레임워크, 라이브러리의 공식 문서를 먼저 검색하고 읽는다.
   - Apple Developer Documentation (developer.apple.com/documentation)
   - 프레임워크별 요구사항: 엔타이틀먼트, Info.plist 키, 권한, 최소 OS 버전
   - API 변경 이력 (Deprecated API, 버전별 차이)

2. **권한/보안 체크리스트**: 시스템 리소스에 접근하는 기능은 아래를 모두 확인한다.
   - [ ] Info.plist에 필요한 Usage Description 키
   - [ ] Entitlements 파일에 필요한 권한 키 (특히 Hardened Runtime 앱)
   - [ ] 코드에서 권한 요청 API 호출
   - [ ] Sandbox vs Non-sandbox 차이
   - [ ] 코드 서명 옵션 (--options runtime 시 추가 요구사항)

3. **기존 동작하는 코드 보호**: 정상 동작하는 코드를 수정할 때는 반드시 근거를 명시한다.
   - 변경 전 동작 확인
   - 변경 이유 문서화
   - 변경 후 동일 시나리오 테스트

4. **구현 전 명세 작성**: 코드를 작성하기 전에 아래를 docs/에 정리한다.
   - 필요한 프레임워크와 API 목록
   - 필요한 권한과 엔타이틀먼트
   - 데이터 흐름과 에러 처리 방식
   - 테스트 시나리오

### 교훈 기록

- **캘린더 권한 (v1.0.3~v1.1.0)**: Hardened Runtime 앱에서 `com.apple.security.personal-information.calendars` 엔타이틀먼트 누락으로 캘린더 권한 다이얼로그가 표시되지 않는 문제 발생. Info.plist의 Usage Description만으로는 부족하며, 엔타이틀먼트 파일이 반드시 필요함. 공식 문서를 먼저 확인했으면 방지할 수 있었음.

---

## 프로젝트 개요

텍스트 또는 이미지에서 LLM을 이용하여 일정 정보를 추출하고, Apple Calendar에 등록하는 macOS 메뉴바 앱.

- **앱 이름**: Yaksok (약속)
- **번들 ID**: com.beret21.yaksok
- **언어**: Swift 6.0, macOS 14+
- **빌드**: Swift Package Manager

## 아키텍처

```text
메뉴바 클릭 / 전역 단축키
→ InputCoordinator (클립보드 텍스트/이미지, 화면 캡처, 선택 텍스트)
→ LLMRouter → Provider (Gemini / OpenAI / Claude / Apple Intelligence)
→ ScheduleEvent (JSON 파싱)
→ ScheduleFormView (SwiftUI 편집 폼)
→ CalendarManager (EventKit) → Calendar.app 등록
```

## 프로젝트 구조

```
Yaksok/
├── Package.swift
├── build.sh                            # 빌드 + .app 패키징 + 코드서명
├── Yaksok.app/                         # 패키징된 .app 번들
│   └── Contents/
│       ├── Info.plist                  # LSUIElement, 캘린더 권한
│       └── MacOS/Yaksok               # 실행 바이너리
├── Sources/Yaksok/
│   ├── App/
│   │   ├── YaksokApp.swift             # @main, NSStatusItem, Edit메뉴, 전역단축키
│   │   └── AppState.swift              # @Observable 중앙 상태
│   ├── LLM/
│   │   ├── LLMProvider.swift           # protocol + 모델 정의
│   │   ├── LLMRouter.swift             # 프로바이더 선택, 라우팅
│   │   ├── SchedulePrompt.swift        # 한국어/영어 시스템 프롬프트
│   │   ├── LLMError.swift              # 에러 enum
│   │   └── Providers/
│   │       ├── GeminiProvider.swift
│   │       ├── OpenAIProvider.swift
│   │       ├── ClaudeProvider.swift
│   │       └── AppleProvider.swift      # macOS 26+ 스텁
│   ├── Calendar/
│   │   ├── CalendarManager.swift        # EventKit 래퍼
│   │   └── ScheduleEvent.swift          # Codable JSON 모델
│   ├── Input/
│   │   ├── InputCoordinator.swift       # 입력 오케스트레이터 (3가지 방식)
│   │   ├── ClipboardReader.swift        # NSPasteboard + 유니버셜 클립보드 (file URL)
│   │   ├── ScreenCaptureManager.swift   # screencapture 명령 기반 캡처
│   │   ├── SelectedTextReader.swift     # AXUIElement + Cmd+C 폴백
│   │   └── HotkeyManager.swift          # Carbon RegisterEventHotKey + HotkeyConfig
│   ├── UI/
│   │   ├── ScheduleFormView.swift       # 일정 편집 폼
│   │   ├── ScheduleFormWindow.swift     # NSWindow 관리
│   │   ├── SettingsView.swift           # 탭 설정 (LLM/API키/단축키/정보)
│   │   ├── KeyRecorderView.swift        # 단축키 입력 캡처 뷰
│   │   ├── ProcessingStatusView.swift   # 처리 중 상태 표시 (NSPopover)
│   │   └── StatusMenuBuilder.swift      # NSMenu 구성
│   ├── Security/
│   │   └── KeychainManager.swift        # API 키 파일 저장 (~/.yaksok/)
│   └── Utilities/
│       ├── Logger.swift                 # os.Logger 래퍼
│       └── ImageConverter.swift         # NSImage → JPEG/base64
└── Resources/
    └── Info.plist                       # SPM 리소스용
```

## 빌드

```bash
cd Yaksok && swift build
cd Yaksok && swift build -c release
```

## 기반 프로젝트

- **MakeSchedule**: LLM 프롬프트, EventKit 연동, SwiftUI 폼 패턴 재활용
- **MacTR (thermalright)**: NSStatusItem 메뉴바 패턴, @Observable 상태, 메모리 관리 재활용

## LLM 프로바이더

| Provider | API | Vision | 기본 모델 |
|----------|-----|--------|-----------|
| Gemini | REST (generativelanguage.googleapis.com) | inlineData | gemini-2.0-flash |
| OpenAI | REST (api.openai.com) | image_url | gpt-4o-mini |
| Claude | REST (api.anthropic.com) | image content block | claude-sonnet-4 |
| Apple | FoundationModels (macOS 26+) | - | Apple Intelligence |

## 보안 정책

### API 키 관리 (필수 준수)

- **모든 API 키는 반드시 macOS Keychain에만 저장한다.**
- 파일, UserDefaults, 하드코딩, URL 쿼리 파라미터 등 평문 저장 절대 금지.
- `KeychainManager`의 `SecItemAdd`/`SecItemCopyMatching` API만 사용.
- `kSecAttrSynchronizable: false` 명시 필수 (iCloud Keychain 동기화 금지).
- 레거시 `~/.yaksok/` 파일이 존재하면 자동 마이그레이션 후 파일 삭제.
- 키 이름: `apiKey_gemini`, `apiKey_openai`, `apiKey_claude`

### 네트워크 보안

- 모든 LLM API 호출은 HTTPS 필수.
- API 키는 반드시 HTTP 헤더로 전송 (URL 쿼리 파라미터 금지).
  - Gemini: `x-goog-api-key` 헤더
  - OpenAI: `Authorization: Bearer` 헤더
  - Claude: `x-api-key` 헤더

### 로그 보안

- 로그 파일: `~/Library/Logs/Yaksok/` (권한 0700/0600)
- 로그에 API 키, 사용자 텍스트 원문, LLM 응답 원문 기록 금지.
- 허용 항목: 모델명, 데이터 크기(bytes), HTTP 상태 코드, 경과 시간.

### 입력 검증

- 외부 입력(URL Scheme, Services, 드래그앤드롭)은 반드시 크기 제한 적용.
- 파일 입력은 크기/타입/심볼릭 링크 검증 필수.

## Apple Intelligence 전략

### 기본 방침

- **Apple Intelligence를 기본 프로바이더로 유지**한다 (API 키 불필요, 100% 로컬, 프라이버시 최강).
- 품질 한계는 프롬프트 최적화와 파이프라인 구조로 극복한다.
- 품질에 불만이 있는 사용자는 Gemini/OpenAI/Claude로 자유롭게 전환 가능.

### 이미지 처리 파이프라인

- 모든 프로바이더는 **OCR → 텍스트 → LLM** 통합 파이프라인을 사용한다.
- Vision OCR(로컬)로 텍스트를 먼저 추출하고, 텍스트만 LLM에 전달한다.
- 이미지를 외부 API로 직접 전송하지 않는다 (프라이버시 + 비용 절감).

### 프롬프트 가이드라인 (필수 준수)

- **프롬프트 예시에 실제 같은 고유명사를 넣지 않는다.**
  - ❌ "서울성모장례식장 2호실", "김인태", "서초구 매헌로8길"
  - ✅ "XX장례식장 N호실", "발표자", "도로명주소"
- 이유: Apple Intelligence(~3B on-device 모델)는 few-shot 예시의 고유명사를 실제 데이터와 혼동할 수 있음.
- Gemini/OpenAI/Claude 같은 대형 모델에서는 발생하지 않지만, 통일된 프롬프트를 위해 모든 예시를 추상화.

### FoundationModels 특성

- `LanguageModelSession`은 100% on-device (오프라인 가능, 데이터 외부 전송 없음).
- ~3B 파라미터 소형 모델 — 프롬프트가 길어지면 품질 저하.
- 세션은 stateful (transcript 유지) — 매 요청마다 새 세션 생성할 것.

## 빌드 & 실행

```bash
# 개발 빌드
swift build

# 릴리즈 빌드 + .app 패키징 + 코드서명
bash build.sh

# 실행
open Yaksok.app
```

## 호출 방식 (구현 완료)

| 방식 | 동작 | 전역 단축키 |
|------|------|-------------|
| 클립보드 | 텍스트/이미지 자동 감지 | Cmd+Shift+E |
| 화면 캡처 | macOS screencapture 영역 선택 | Cmd+Shift+Option+S |
| 선택 텍스트 | AXUIElement + Cmd+C 폴백 | Cmd+Shift+D |

### 추가 호출 방식 (구현 완료)
4. 드래그앤드롭
5. Services 메뉴
6. Shortcuts.app 연동
7. URL Scheme

## 메모리 관리

- autoreleasepool: 이미지 처리 감싸기
- weak self: 모든 클로저
- URLSession: .ephemeral 세션 (캐시 방지)
- 이미지 즉시 해제: LLM 전송 후 nil
- 목표: 대기 ~20MB, 피크 ~40MB

## 개발 히스토리

- 2026-03-31: Phase 1 완료 (MVP - 클립보드 텍스트/이미지 → Gemini → 폼 → 캘린더)
- 2026-03-31: Phase 2 완료 (멀티 LLM - OpenAI, Claude, Apple 스텁)
- 2026-03-31: Phase 3 완료 (전역 단축키, 화면 캡처, 선택 텍스트)
- 2026-03-31: .app 번들 패키징 + adhoc 코드서명
- 2026-03-31: Keychain → 파일 기반 저장으로 변경 (개발 중 대화상자 방지)
- 2026-03-31: Edit 메뉴 추가 (Cmd+C/V/X/A 지원)
- 2026-04-01: 채팅 대화 이미지 추출 지원 (프롬프트에 오늘 날짜 + 채팅 패턴 추가)
- 2026-04-01: 기차/항공 승차권 프롬프트 강화 (SRT, KTX, DB ICE, 항공권)
- 2026-04-01: 온라인 미팅 링크 분리 + 참석자 추출 규칙 추가
- 2026-04-01: JSON 파싱 3단계 폴백 (JSONDecoder → 배열 → JSONSerialization)
- 2026-04-01: 처리 중 NSPopover 상태 표시 (프로바이더명 + 경과 시간)
- 2026-04-01: 단축키 설정 UI (KeyRecorderView)
- 2026-04-01: ClipboardReader 유니버셜 클립보드 지원 (file URL reference)
- 2026-04-01: 로그 파일 /tmp/yaksok_YYYY.log (MakeSchedule 패턴)
- 2026-04-01: Apple Intelligence 실제 구현 (FoundationModels + Vision OCR 파이프라인)
- 2026-04-01: 기본 프로바이더를 Apple Intelligence로 변경 (API 키 불필요)
- 2026-04-01: URL Scheme (yaksok://extract, clipboard, capture, selection)
- 2026-04-01: Services 메뉴 (NSServices in Info.plist)
- 2026-04-01: 드래그앤드롭 (StatusBarDragDelegate)
- 2026-04-01: Shortcuts.app 연동 (AppIntents)
- 2026-04-01: 로그인 시 자동 시작 (SMAppService)
- 2026-04-01: 최근 등록 히스토리 (메뉴 표시, 최대 5건)
- 2026-04-01: 온보딩 화면 (Apple Intelligence 기본 + 외부 LLM 선택사항)
- 2026-04-01: macOS 버전 체크 (설정에서 Apple Intelligence 지원 여부 표시)
- 2026-04-01: Package.swift swift-tools-version 6.2, macOS 26 타겟
- 2026-04-01: 히스토리 구조 개선 (status: recognized/registered/cancelled, providerName)
- 2026-04-01: 히스토리 UI 탭 (필터, 목록, 삭제), 보관 정책 (100건/90일)
- 2026-04-01: 보안 점검 — API 키 Keychain 전환, Gemini 헤더 전송, 로그 민감정보 제거
- 2026-04-01: 메모리 누수 수정 — Timer→TimelineView, static URLSession, autoreleasepool
- 2026-04-01: OCR 통합 파이프라인 — 모든 프로바이더 텍스트 경로 통일 (이미지 외부 전송 없음)
- 2026-04-01: 프롬프트 재구성 — 예시 JSON 전부 제거, 800자로 축소 (Apple Intelligence 최적화)
- 2026-04-01: 일정 충돌 인지 — DayTimelineView (기존=그레이, 신규=그린/레드), 설정에서 캘린더 선택
- 2026-04-01: 기본 회의 시간 설정 (15분/30분/1시간/1.5시간/2시간)
- 2026-04-01: 입력 길이 제한 (텍스트 5,000자, 이미지 10MB) — InputCoordinator 중앙 검증
- 2026-04-02: 재분석 버튼 (Gemini/GPT/Claude로 폼에서 1-click 재추출)
- 2026-04-02: 날짜 후처리 — 과거 날짜→내일, 비합리적 종료시간 보정
- 2026-04-02: 시간 입력 버그 수정 (onChange→onSubmit 전환)
- 2026-04-02: 중복 추출 차단 (처리 중/폼 열림 시 새 추출 무시)
- 2026-04-02: 동적 모델 목록 — Gemini/OpenAI API에서 모델 가져오기 + 캐시 + 1주 자동 갱신
- 2026-04-02: 설정 UI — 캘린더 계정별 DisclosureGroup 그룹핑
- 2026-04-02: 에러 메시지 개선 — 타임아웃/오프라인/인증실패 안내
- 2026-04-02: Share Extension (.appex) — 공유 메뉴에서 텍스트 전달
- 2026-04-02: 앱 아이콘 생성 (오렌지 캘린더)
- 2026-04-02: Developer ID 코드서명 (DT9JQA4X82)
- 2026-04-02: Xcode 26.4 툴체인 전환 (xcode-select)
- 2026-04-02: Gemini 프롬프트 대폭 개선 — 2,500자, 일정 유형별 상세 규칙, 500건 스트레스 테스트 95.7%
- 2026-04-02: 종일 일정 폴백 — LLM 실패 시 날짜 패턴으로 코드 레벨 종일 일정 생성
- 2026-04-02: Apple Intelligence 프롬프트 가이드 문서 (docs/ + Notion)
- 2026-04-02: Sparkle 자동 업데이트 — SPM 의존성, 메뉴/설정 UI, build.sh 임베딩/서명, appcast.xml
- 2026-04-02: GitHub 공개 repo (beret21/Yaksok) — 소스 공개 (SchedulePrompt 간소화), build.sh SIGN_ID 환경변수화
- 2026-04-02: Apple 공증(notarization) — build.sh --sign --zip 파이프라인 자동화
- 2026-04-02: 온보딩 3페이지 (환영→캘린더 권한→선택 권한) — AXIsProcessTrusted/CGPreflight 실시간 체크
- 2026-04-02: 메뉴 개선 — 상단 v/Provider/Model 표시, Claude 모델 API fetch
- 2026-04-02: ModelFetcher ephemeral URLSession 전환 (메모리 누수 수정)
- 2026-04-02: 설정 > 일정 충돌 체크 — 캘린더 권한 요청/시스템 설정 버튼 추가

## 자동 업데이트 (Sparkle)

### 구조
- **Sparkle 2.x** SPM 의존성 (Package.swift)
- **SPUStandardUpdaterController**: YaksokApp.swift에서 초기화, 메뉴/설정에 전달
- **EdDSA 서명**: macTR과 동일 키 공유 (Keychain `ed25519`)
- **SUFeedURL**: `https://raw.githubusercontent.com/beret21/Yaksok/main/appcast.xml`
- **자동 체크**: 24시간 간격 (SUScheduledCheckInterval: 86400)

### 릴리즈 절차
1. `Resources/Info.plist`에서 CFBundleVersion + CFBundleShortVersionString 업데이트
2. `bash build.sh --sign --zip` 실행
3. 출력된 edSignature + length를 appcast.xml에 기입
4. GitHub에 릴리즈 생성 + ZIP 업로드
5. appcast.xml push

### 빌드 플래그
- `build.sh` — 개발용 ad-hoc 서명
- `build.sh --sign` — Developer ID 서명 (/tmp에서 Dropbox xattr 우회)
- `build.sh --sign --zip` — 서명 + Sparkle 배포용 ZIP 생성

## 알려진 이슈

- 캘린더 권한: .app 번들로 실행해야 시스템 설정에 표시됨 (`open Yaksok.app`)
- Apple Intelligence (~3B): 구조화된 일정 추출에 한계, Gemini 기본 프로바이더 권장
- 처리 중 팝업: NSPopover 기반. Bartender로 아이콘 숨기면 좌측 상단 숨김 영역에서 표시됨
- @Generable: Xcode 툴체인 필수, instructions 분리 시 ~3B 모델 혼동 — 추가 테스트 필요

## 로그

```bash
tail -f ~/Library/Logs/Yaksok/yaksok_$(date +%Y).log
```


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>