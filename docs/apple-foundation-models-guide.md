# Apple Foundation Models Framework — 개발자 프롬프트 가이드

## 모델 특성

| 항목 | 상세 |
|------|------|
| 파라미터 | ~3B (2-bit QAT 양자화) |
| 컨텍스트 윈도우 | 4,096 토큰 (입력+출력 합산) |
| 토큰 추정 | 영어: ~3-4자/토큰, 한국어: ~1자/토큰 |
| 비전 인코더 | ViTDet-L 300M (이미지 이해) |
| 다국어 | 15개 언어 (한국어 포함) |
| 추론 위치 | 100% 온디바이스, 오프라인 가능 |

### 잘하는 것
- 요약 (Summarization)
- 엔티티 추출 (Entity Extraction)
- 텍스트 이해/분류 (Classification)
- 짧은 대화 (Short Dialog)
- 태그 생성 (Tag Generation)
- 텍스트 수정 (Revision)

### 못하는 것
- 복잡한 다단계 추론 → 태스크를 단순 단계로 분할
- 수학 계산 → 전통적 코드 사용
- 코드 생성 → 최적화되지 않음
- 세계 지식/사실 기억 → 할루시네이션 위험
- 긴 출력 → 4,096 토큰 제한

---

## 핵심 아키텍처

### Session 관리

```swift
import FoundationModels

// 기본 세션
let session = LanguageModelSession()
let response = try await session.respond(to: "프롬프트")

// Instructions(시스템 프롬프트)와 함께
let session = LanguageModelSession(
    instructions: "일정 정보를 추출하는 도우미입니다."
)
```

**세션 원칙:**
- 세션은 stateful — transcript(대화 이력)가 누적됨
- 독립 태스크마다 새 세션 생성 (요약, 번역, 분류 등)
- 멀티턴 대화에만 세션 재사용
- 한 번에 하나의 요청만 처리 가능

**Prewarm (사전 로딩):**
```swift
await session.prewarm()  // 유휴 시간에 모델 미리 로드
```

### Instructions vs. Prompts

| 구분 | Instructions | Prompts |
|------|-------------|---------|
| 설정 시점 | 세션 생성 시 | 매 요청마다 |
| 지속성 | 세션 전체에 적용 | 현재 요청만 |
| 우선순위 | Prompt보다 우선 | Instructions에 종속 |
| 보안 | 신뢰할 수 있는 개발자 콘텐츠만 | 사용자 입력 포함 가능 |

**중요: Instructions에 사용자 입력을 절대 포함하지 마세요** (프롬프트 인젝션 방지)

---

## @Generable — 구조화된 출력 (Guided Generation)

가장 중요한 기능. 자유 텍스트 JSON 대신 Swift 타입으로 출력을 강제합니다.

```swift
@Generable
struct ScheduleEvent {
    @Guide(description: "일정 제목")
    let title: String

    @Guide(description: "시작 날짜 YYYY-MM-DD")
    let startDate: String

    @Guide(description: "시작 시간 HH:MM (24시간제)")
    let startTime: String

    @Guide(description: "종료 날짜 YYYY-MM-DD")
    let endDate: String

    @Guide(description: "종료 시간 HH:MM")
    let endTime: String

    @Guide(description: "종일 일정 여부")
    let allDay: Bool

    @Guide(description: "장소")
    let location: String

    @Guide(description: "메모")
    let notes: String
}

let session = LanguageModelSession(
    instructions: "텍스트에서 일정 정보를 추출합니다."
)
let response = try await session.respond(
    to: userText,
    generating: ScheduleEvent.self
)
let event = response.content  // 타입 안전한 ScheduleEvent
```

### @Guide 제약 조건

```swift
@Generable
struct NPC {
    @Guide(description: "캐릭터 이름")
    let name: String

    @Guide(.range(1...10))
    let level: Int

    @Guide(.count(3))
    let attributes: [Attribute]

    @Guide(.anyOf(["warrior", "mage", "rogue"]))
    let characterClass: String
}
```

| 타입 | 제약 |
|------|------|
| String | `.anyOf([...])`, `.constant("value")`, `.regex(...)`, `description:` |
| Int/Double | `.minimum()`, `.maximum()`, `.range(...)` |
| Array | `.count(n)`, `.minimumCount(n)`, `.maximumCount(n)` |

### Guided Generation 장점
- **프롬프트 단순화** — 출력 형식을 설명할 필요 없음
- **정확도 향상** — constrained decoding이 유효한 토큰만 허용
- **성능 최적화** — speculative decoding 가능
- **타입 안전성** — 파싱 불필요, Swift 객체 직접 반환

### 프로퍼티 선언 순서가 중요
- @Generable 프로퍼티는 **선언 순서대로** 생성됨
- 의존 관계가 있는 프로퍼티는 뒤에 배치
- **요약/종합 프로퍼티는 맨 마지막에** (앞선 필드를 참고하여 더 나은 품질)

---

## 프롬프트 엔지니어링 원칙

### 1. 간결하게 작성
- 모든 토큰이 레이턴시에 영향 → 지시사항을 최소화
- ~3B 모델은 프롬프트가 길어지면 품질 저하
- 4,096 토큰 제한을 항상 고려

### 2. 명확하고 직접적인 지시
```
❌ "일정 정보가 있다면 추출해 주시면 감사하겠습니다"
✅ "텍스트에서 일정을 추출해. JSON만 출력해."
```

### 3. 출력 길이 제어
- "세 문장으로", "한 단어로", "한 문단으로" 등 명시

### 4. 역할/페르소나 부여
```swift
instructions: "당신은 일정 관리 비서입니다. 항상 간결하게 응답합니다."
```

### 5. Few-shot 예시 (5개 미만)
```swift
instructions: """
    일정을 추출합니다.

    예시 입력: "내일 3시 회의"
    예시 출력: {"title": "회의", "start_date": "2026-04-03", ...}
    """
```

**주의 (Yaksok 프로젝트에서 발견):**
- 예시에 실제 같은 고유명사 사용 금지
- ~3B 모델은 예시의 고유명사를 실제 데이터와 혼동
- `❌ "서울성모장례식장"` → `✅ "XX장례식장"`

### 6. 강조에 대문자 사용
```
"DO NOT include personal information"
"ALWAYS use YYYY-MM-DD format"
```

### 7. 부정 지시 활용
```
"일정이 없으면 에러 JSON을 반환해. 설명 없이."
```

---

## 컨텍스트 윈도우 관리 (4,096 토큰)

### 토큰 측정 API (iOS 26.4+)
```swift
let model = SystemLanguageModel.default
let contextSize = try await model.contextSize  // 4096

// Instructions 토큰 수 측정
let usage = try await model.tokenUsage(for: instructions)

// 전체 transcript 토큰 수
let usage = try await model.tokenUsage(for: session.transcript)
```

### 컨텍스트 초과 처리
```swift
do {
    let response = try await session.respond(to: prompt)
} catch LanguageModelSession.GenerationError.exceededContextWindowSize {
    // 새 세션 생성, 첫 번째와 마지막 엔트리만 보존
    let entries = session.transcript.entries
    var condensed = [Transcript.Entry]()
    if let first = entries.first { condensed.append(first) }
    if entries.count > 1, let last = entries.last { condensed.append(last) }
    session = LanguageModelSession(transcript: Transcript(entries: condensed))
}
```

### 관리 전략
1. **슬라이딩 윈도우** — 오래된 엔트리 삭제, 최근 유지
2. **용량 70-80%에서 요약** — 대화 요약 후 새 세션
3. **단일 턴 사용** — 독립 태스크마다 새 세션 (가장 단순)

---

## 스트리밍 (Snapshot 기반)

```swift
@Generable struct Itinerary {
    var name: String
    var days: [Day]
}
// 자동 생성: Itinerary.PartiallyGenerated { var name: String?; var days: [Day]? }

let stream = session.streamResponse(
    to: "3일 여행 계획 짜줘",
    generating: Itinerary.self
)
for try await partial in stream {
    self.itinerary = partial  // UI 점진적 업데이트
}
```

---

## Tool Calling

```swift
struct GetWeatherTool: Tool {
    let name = "getWeather"
    let description = "도시의 현재 날씨 조회"

    @Generable
    struct Arguments {
        @Guide(description: "도시 이름")
        var city: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let weather = try await WeatherService.fetch(for: arguments.city)
        return ToolOutput("현재 \(weather.temperature)°C")
    }
}

let session = LanguageModelSession(tools: [GetWeatherTool()])
```

**주의사항:**
- 도구 이름/설명은 프롬프트에 그대로 삽입됨 → **짧게**
- 도구 정의가 토큰을 소비 (간단한 도구도 ~63토큰)
- 복수 도구 병렬 실행 가능 → thread-safe 필수

---

## Generation Options

```swift
// 결정적 출력 (같은 프롬프트 = 같은 결과)
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(sampling: .greedy)
)

// 온도 조절
let options = GenerationOptions(
    temperature: 0.5,              // 0.3-0.6: 안정적, 1.2-2.0: 창의적
    maximumResponseTokens: 200
)
```

| 온도 범위 | 용도 |
|----------|------|
| 0.3-0.6 | UI 힌트, 요약, 엔티티 추출 |
| ~0.5 | 범용 어시스턴트 |
| 1.2-2.0 | 창작, 브레인스토밍 |

---

## 안전 가드레일

- **입력/출력 2중 필터** — 비활성화 불가
- 프롬프트 인젝션 방지: Instructions에 사용자 입력 금지
- 가드레일 위반 시 `GenerationError.guardrailViolation` throw

### 사용자 입력 패턴 (리스크 순)
1. **Curated** (최저 위험): 사전 정의 옵션에서 선택
2. **Combined** (중간): 사용자 입력을 개발자 템플릿에 삽입
3. **Direct** (최고 위험): 사용자 텍스트를 그대로 프롬프트로

---

## 가용성 확인

```swift
switch SystemLanguageModel.default.availability {
case .available:
    // 사용 가능
case .unavailable(.appleIntelligenceNotEnabled):
    // Apple Intelligence 미활성화
case .unavailable(.deviceNotEligible):
    // 미지원 디바이스
case .unavailable(.modelNotReady):
    // 모델 다운로드 중
}
```

---

## 성능 최적화 요약

| 기법 | 효과 |
|------|------|
| `session.prewarm()` | 콜드 스타트 제거 |
| Instructions 최소화 | 토큰 절약 = 낮은 레이턴시 |
| @Generable 사용 | speculative decoding 활성화 |
| 도구 이름/설명 짧게 | 토큰 절약 |
| `.greedy` 샘플링 | 결정적 태스크에 빠름 |
| 미사용 @Generable 프로퍼티 제거 | 모든 프로퍼티가 생성됨 |
| 요약 프로퍼티 마지막 선언 | 앞선 필드 참고하여 품질 향상 |
| 단일 턴 세션 | 컨텍스트 누적 방지 |

---

## 서버 LLM과의 비교

| 항목 | 온디바이스 (~3B) | 서버 LLM (100B+) |
|------|-----------------|-------------------|
| 컨텍스트 | 4,096 토큰 | 128K-1M+ 토큰 |
| 세계 지식 | 매우 제한적 | 광범위 |
| 복잡한 추론 | 약함 | 강함 |
| 코드 생성 | 미권장 | 가능 |
| 수학 | 미권장 | 가능 |
| 프라이버시 | 100% 온디바이스 | 데이터 전송 |
| 비용 | 무료 | 토큰당 과금 |
| 오프라인 | 가능 | 불가 |

---

## Yaksok 프로젝트 적용 시사점

### 현재 방식 (자유 텍스트 JSON)
- 프롬프트에서 JSON 형식을 텍스트로 지시
- ~3B 모델이 지시를 무시하는 경우 빈번 (날짜 기본값, 부고 형식 등)
- 코드 레벨 후처리로 보완

### 권장 방식 (@Generable 전환)
```swift
@Generable
struct ExtractedSchedule {
    @Guide(description: "일정 제목 - 텍스트의 실제 내용 그대로")
    let title: String

    @Guide(description: "시작 날짜 YYYY-MM-DD")
    let startDate: String

    @Guide(description: "시작 시간 HH:MM 24시간제, 없으면 09:00")
    let startTime: String

    @Guide(description: "종료 날짜 YYYY-MM-DD")
    let endDate: String

    @Guide(description: "종료 시간 HH:MM, 없으면 시작+1시간")
    let endTime: String

    @Guide(description: "종일 일정 여부")
    let allDay: Bool

    @Guide(description: "장소 - 텍스트 그대로")
    let location: String

    @Guide(description: "메모 - 참석자, 링크 등")
    let notes: String
}
```

**기대 효과:**
1. constrained decoding으로 JSON 파싱 실패 제거
2. 필드별 @Guide로 모델이 각 필드의 의미를 정확히 이해
3. 프롬프트 대폭 단축 가능 (형식 설명 불필요)
4. 타입 안전성 — 파싱 폴백 로직 불필요

---

## 참고 자료

- [Meet the Foundation Models framework (WWDC25-286)](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Deep dive into Foundation Models (WWDC25-301)](https://developer.apple.com/videos/play/wwdc2025/301/)
- [Explore prompt design & safety (WWDC25-248)](https://developer.apple.com/videos/play/wwdc2025/248/)
- [Generating content with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [TN3193: Managing the Context Window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Apple Foundation Models 2025 Updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
