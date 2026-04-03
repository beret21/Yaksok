# Yaksok — TODO (다음 세션 작업)

## 우선순위 높음

### 1. 히스토리 구조 개선
- **문제**: "최근 등록"에 취소한 건도 기록됨 (버그)
- **해결**:
  - `HistoryItem`에 `status` 필드 추가: `.registered`, `.recognized`, `.cancelled`
  - 등록 완료 시에만 `.registered`로 기록
  - LLM 추출 완료 시 `.recognized`로 기록 (디버깅용)
  - 취소 시 `.cancelled`로 기록

### 2. 히스토리 UI (설정 탭)
- SettingsView에 **"히스토리"** 탭 추가
- 등록 목록과 인식 목록 분리 표시
- 각 항목: 제목, 날짜, 시간, 상태 (등록/인식/취소), 사용한 LLM
- "히스토리 지우기" 버튼
- 메뉴바 드롭다운에는 등록된 것만 최근 5개 표시

### 3. 히스토리 보관 정책
- 건수 제한: 최대 100건 (초과 시 오래된 것부터 삭제)
- 기간 제한: 90일 이상 된 항목 자동 삭제
- 앱 시작 시 정리 실행

## 우선순위 중간

### 4. Services 메뉴 동작 확인
- Info.plist NSServices 등록은 완료됨
- macOS Services 캐시 갱신에 시간 소요 — `/System/Library/CoreServices/pbs -flush` 시도
- 텍스트 선택 → 우클릭 → 서비스 → "Yaksok으로 일정 등록" 동작 검증

### 5. 드래그앤드롭 동작 확인
- NSStatusBarButton의 window에 drag type 등록은 되어 있음
- 실제 이미지 파일 드래그 테스트 필요
- Finder에서 .png/.jpg 파일 드래그 시 동작 확인

### 6. Shortcuts.app 동작 확인
- AppIntents 등록은 되어 있음
- 단축어 앱에서 "Yaksok" 검색 → 액션 표시 확인
- "약속 추출해줘" Siri 음성 명령 테스트

## 우선순위 낮음

### 7. UI 다듬기
- 앱 아이콘 (현재 기본 아이콘)
- 다크 모드 테스트
- 폼 윈도우 크기 조정 (긴 메모일 때)

### 8. 에러 처리 개선
- 네트워크 타임아웃 시 재시도 버튼
- Apple Intelligence 모델 다운로드 안내 (최초 사용 시)
- 캘린더 권한 거부 시 안내 개선

### 9. 성능 최적화
- Apple Intelligence 응답 속도 (~19초) — 프롬프트 길이 줄이기 실험
- 이미지 크기 최적화 (큰 이미지 리사이즈 후 전송)
- 메모리 프로파일링 (Activity Monitor로 5회 반복 사용 후 확인)

### 10. 문서 정리
- README.md에 Apple Intelligence 기본 프로바이더 반영
- CLAUDE.md 최종 업데이트
- 스크린샷 추가 (온보딩, 설정, 일정 폼)

## 완료된 항목 (이번 세션)

- [x] Phase 1: MVP (클립보드 → Gemini → 폼 → 캘린더)
- [x] Phase 2: 멀티 LLM (Gemini/OpenAI/Claude) + Vision
- [x] Phase 3: 화면 캡처, 선택 텍스트, 전역 단축키
- [x] Phase 4: URL Scheme, Services 메뉴, 드래그앤드롭, Shortcuts.app
- [x] .app 번들 패키징 + adhoc 코드서명
- [x] Apple Intelligence 실제 구현 (FoundationModels + Vision OCR)
- [x] 처리 중 NSPopover 상태 표시
- [x] 단축키 설정 UI (KeyRecorderView)
- [x] 온보딩 화면 (Apple Intelligence 기본)
- [x] 로그인 시 자동 시작 (SMAppService)
- [x] 최근 등록 히스토리 (메뉴 표시)
- [x] 기차표/항공권/채팅 대화 프롬프트
- [x] 유니버셜 클립보드 지원 (file URL)
- [x] JSON 3단계 폴백 파싱
- [x] macOS 버전별 기능 안내
- [x] 파일 기반 로그 (/tmp/yaksok_YYYY.log)
