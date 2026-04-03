# Yaksok (약속)

텍스트 또는 이미지에서 LLM으로 일정을 추출하여 Apple Calendar에 등록하는 macOS 메뉴바 앱.

## 주요 기능

- **다양한 입력**: 클립보드, 화면 캡처, 선택 텍스트, 드래그앤드롭, Services 메뉴, URL Scheme, Shortcuts
- **멀티 LLM**: Apple Intelligence (온디바이스), Google Gemini, OpenAI GPT, Anthropic Claude
- **프라이버시 OCR**: 이미지 → Vision OCR (로컬) → 텍스트만 LLM 전송 (이미지 외부 전송 없음)
- **재분석**: Apple Intelligence 결과가 부정확할 때 Gemini/GPT/Claude로 1-click 재추출
- **일정 충돌 인지**: 기존 캘린더 일정을 타임라인으로 시각화
- **전역 단축키**: 어떤 앱에서든 즉시 호출
- **캘린더 자동 감지**: 시스템에 등록된 모든 캘린더 계정(iCloud, Google, Exchange 등) 자동 인식

## 지원 일정 유형

| 유형 | 추출 결과 |
|------|----------|
| 회의/미팅 | 제목, 날짜/시간, 장소, 참석자 |
| 부고/장례 | 문상 방문 일정 (1시간), 빈소 장소 |
| 승차권 (SRT/KTX/항공) | 편명(호차-좌석), 출발-도착역, 시간 |
| 채팅 대화 | 합의된 일정, 참석자 |
| 온라인 미팅 | 플랫폼명, 미팅 링크 |

## 호출 방식

| 방식 | 설명 | 기본 단축키 |
|------|------|-------------|
| 클립보드 | 텍스트/이미지 자동 감지 | `Cmd+Shift+E` |
| 화면 캡처 | 영역 선택 후 OCR 추출 | `Cmd+Shift+Option+S` |
| 선택 텍스트 | 현재 앱에서 선택한 텍스트 | `Cmd+Shift+D` |
| 드래그앤드롭 | 메뉴바 아이콘에 파일 드롭 | - |
| Services | 우클릭 > 서비스 > Yaksok | - |
| URL Scheme | `yaksok://extract` | - |
| Shortcuts | 단축어 앱에서 Yaksok 액션 | - |

## 요구 사항

- macOS 14+ (Apple Intelligence는 macOS 26+)
- Apple Silicon (M1 이상)
- Swift 6.2+ / Xcode 26+

## 설치

### 다운로드 (권장)
[**Yaksok-1.0.0.zip 다운로드**](https://github.com/beret21/Yaksok/releases/latest/download/Yaksok-1.0.0.zip) — Developer ID 서명 + Apple 공증 완료

압축 해제 후 `Yaksok.app`을 `/Applications`에 이동하여 실행합니다.

### 소스 빌드
```bash
git clone https://github.com/beret21/Yaksok.git
cd Yaksok
bash build.sh
open Yaksok.app
```

## LLM 프로바이더

| Provider | API 키 | 기본 모델 | 특징 |
|----------|--------|----------|------|
| Apple Intelligence | 불필요 | 온디바이스 ~3B | 무료, 오프라인, 프라이버시 |
| Google Gemini | 필요 | gemini-2.0-flash | 빠르고 저렴 |
| OpenAI | 필요 | gpt-4o-mini | 범용 |
| Claude | 필요 | claude-sonnet-4 | 정확도 우수 |

설정 > API 키 탭에서 각 프로바이더의 API 키를 입력합니다. 모델 목록은 API에서 자동으로 가져옵니다.

## 보안

- API 키: macOS Keychain 저장 (iCloud 동기화 금지)
- 이미지: 외부 API 미전송 (Vision OCR → 텍스트만 전송)
- 로그: API 키, 사용자 텍스트 원문, LLM 응답 원문 기록 안 함
- 네트워크: HTTPS 전용, API 키는 HTTP 헤더로 전송

## 프로젝트 구조

```
Sources/Yaksok/
├── App/          # YaksokApp, AppState
├── LLM/          # LLMProvider, LLMRouter, ModelFetcher, Providers/
├── Calendar/     # CalendarManager, ScheduleEvent
├── Input/        # InputCoordinator, ClipboardReader, ScreenCapture, OCR
├── UI/           # ScheduleFormView, SettingsView, StatusMenu, DayTimeline
├── Security/     # KeychainManager
└── Utilities/    # Logger, ImageConverter
```

## 라이선스

MIT License

## 후원

Yaksok이 유용하셨다면 커피 한 잔 사주세요!

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/beret21)

## 저자

Yoonseok Jang ([@beret21](https://github.com/beret21))
