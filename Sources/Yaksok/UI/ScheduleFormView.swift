import SwiftUI
import EventKit

/// Event editing form — adapted from MakeSchedule/ScheduleFormView.swift
struct ScheduleFormView: View {
    let event: ScheduleEvent
    let onDismiss: () -> Void
    var onRegistered: ((String, String) -> Void)?  // (title, date)
    var onCancelled: (() -> Void)?
    var onReanalyze: (@MainActor @Sendable (LLMProviderID) async -> ScheduleEvent?)?
    var providerName: String = ""
    var conflictCheckCalendarIDs: Set<String> = []
    var defaultDurationMinutes: Int = 60

    @State private var calendarManager = CalendarManager()

    @State private var title: String = ""
    @State private var isAllDay: Bool = false
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedCalendarID: String = ""
    @State private var showError: Bool = false
    @State private var errorText: String = ""
    @State private var isRegistered: Bool = false

    // Time text input
    @State private var startTimeText: String = "19:00"
    @State private var endTimeText: String = "20:00"
    @State private var startTimeValid: Bool = true
    @State private var endTimeValid: Bool = true

    @State private var existingEvents: [EKEvent] = []
    @State private var suppressAutoAdvance = false

    // Re-analysis state
    @State private var isReanalyzing = false
    @State private var reanalyzeError: String?
    @State private var currentProviderName: String = ""

    private var showTimeline: Bool { !conflictCheckCalendarIDs.isEmpty }

    private let accentOrange = Color(red: 0.95, green: 0.45, blue: 0.25)

    var body: some View {
        HStack(spacing: 0) {
            // Left: Form
            VStack(spacing: 0) {
                headerView
                    .padding(.top, 20)
                    .padding(.bottom, 4)

                if onReanalyze != nil {
                    reanalyzeSection
                        .padding(.bottom, 10)
                }

                if calendarManager.authorizationChecked && !calendarManager.accessGranted {
                    permissionDeniedView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            titleSection
                            sectionDivider
                            dateTimeSection
                            sectionDivider
                            detailsSection
                            sectionDivider
                            calendarSection
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                    }

                    Spacer(minLength: 8)
                    footerButtons
                        .padding(.bottom, 16)
                }
            }
            .frame(width: 520)

            // Right: Timeline (only when conflict calendars configured)
            if showTimeline {
                Divider()
                DayTimelineView(
                    existingEvents: existingEvents,
                    newStart: startDate,
                    newEnd: endDate,
                    isAllDay: isAllDay
                )
                .padding(.trailing, 4)
            }
        }
        .frame(width: showTimeline ? 650 : 520, height: 620)
        .onAppear {
            populateFromEvent()
            calendarManager.requestAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            // 캘린더 추가/삭제 시 피커 목록도 갱신
            validateSelectedCalendar()
            loadConflictEvents()
        }
        .onChange(of: calendarManager.calendars) { _, cals in
            selectDefaultCalendar(from: cals)
            loadConflictEvents()
        }
        .onChange(of: startDate) { oldVal, newVal in
            guard !suppressAutoAdvance else { return }
            // Auto-advance end date by same delta
            let delta = newVal.timeIntervalSince(oldVal)
            if delta != 0 {
                endDate = endDate.addingTimeInterval(delta)
                syncTimeTexts()
            }
            loadConflictEvents()
        }
        .onChange(of: endDate) { _, _ in loadConflictEvents() }
        .alert(String(localized: "오류", comment: "Error alert title"), isPresented: $showError) {
            Button(String(localized: "확인", comment: "OK button")) {}
        } message: {
            Text(errorText)
        }
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("캘린더 접근 권한이 필요합니다", comment: "Calendar permission needed")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Text("1.")
                        .font(.callout.weight(.bold))
                        .foregroundColor(accentOrange)
                        .frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("아래 버튼으로 시스템 설정을 열고,\nYaksok에 **'전체 캘린더 접근'** 권한을\n허용해 주세요.", comment: "Permission step 1")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: { calendarManager.openSystemSettings() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "gear")
                                Text("시스템 설정 열기", comment: "Open System Settings")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentOrange)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Text("2.")
                        .font(.callout.weight(.bold))
                        .foregroundColor(accentOrange)
                        .frame(width: 20, alignment: .trailing)
                    Text("권한 설정 후 Yaksok을 다시 시도해 주세요.", comment: "Permission step 2")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)

            // TCC 캐시 리셋 안내
            VStack(spacing: 6) {
                Text("시스템 설정에 Yaksok이 보이지 않으면:", comment: "TCC reset hint")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("tccutil reset Calendar com.beret21.yaksok")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08)))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("tccutil reset Calendar com.beret21.yaksok", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "터미널 명령어 복사", comment: "Copy command"))
                }
                Text("위 명령어를 터미널에서 실행 후 앱을 재시작하세요.", comment: "TCC reset instruction")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()

            HStack {
                Button {
                    calendarManager.accessGranted = false
                    calendarManager.authorizationChecked = false
                    calendarManager.requestAccess()
                } label: {
                    Text("다시 확인", comment: "Recheck permission")
                }

                Spacer()

                Button(action: onDismiss) {
                    Text("닫기", comment: "Close button")
                        .frame(width: 72)
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentOrange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accentOrange)
            }
            Text("일정 등록", comment: "Schedule registration header")
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(String(localized: "제목", comment: "Title label"), icon: "pencil")
            TextField(String(localized: "일정 제목을 입력하세요", comment: "Title placeholder"), text: $title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            title.isEmpty ? Color.secondary.opacity(0.2) : accentOrange.opacity(0.5),
                            lineWidth: 1
                        )
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Date & Time Section

    private let fieldLabelWidth: CGFloat = 40

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel(String(localized: "종일", comment: "All-day label"), icon: "sun.max")
                Spacer()
                Toggle("", isOn: $isAllDay.animation(.easeInOut(duration: 0.25)))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(accentOrange)
                    .onChange(of: isAllDay) { _, newValue in
                        if !newValue {
                            // 종일 → 시간 지정 전환: 09:00 시작, 기본 회의 시간 적용
                            suppressAutoAdvance = true
                            let cal = Calendar.current
                            startDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: startDate) ?? startDate
                            endDate = startDate.addingTimeInterval(Double(defaultDurationMinutes) * 60)
                            // Reset flag after SwiftUI onChange handlers have fired
                            DispatchQueue.main.async { suppressAutoAdvance = false }
                        }
                        syncTimeFields()
                    }
            }

            // Start row
            HStack(spacing: 8) {
                Text("시작", comment: "Start label")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(width: fieldLabelWidth, alignment: .trailing)

                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)

                if !isAllDay {
                    timeField(text: $startTimeText, isValid: $startTimeValid, date: $startDate, base: startDate)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Spacer()
            }

            // End row
            HStack(spacing: 8) {
                Text("종료", comment: "End label")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(width: fieldLabelWidth, alignment: .trailing)

                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)

                if !isAllDay {
                    timeField(text: $endTimeText, isValid: $endTimeValid, date: $endDate, base: endDate)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Time Field

    private func timeField(
        text: Binding<String>,
        isValid: Binding<Bool>,
        date: Binding<Date>,
        base: Date
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(isValid.wrappedValue ? .secondary : .red)

            TextField("HH:MM", text: text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .frame(width: 56)
                .multilineTextAlignment(.center)
                .onChange(of: text.wrappedValue) { _, val in
                    // Visual validation only — don't apply to date mid-typing
                    isValid.wrappedValue = isValidTimeFormat(val)
                }
                .onSubmit {
                    // Apply on Enter
                    let valid = validateAndApplyTime(text.wrappedValue, to: &date.wrappedValue, base: base)
                    isValid.wrappedValue = valid
                    if valid { syncTimeTexts() }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isValid.wrappedValue ? Color.secondary.opacity(0.25) : Color.red.opacity(0.6),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel(String(localized: "장소", comment: "Location label"), icon: "mappin.and.ellipse")
                TextField(String(localized: "장소를 입력하세요", comment: "Location placeholder"), text: $location)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel(String(localized: "메모", comment: "Notes label"), icon: "note.text")
                TextEditor(text: $notes)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80, maxHeight: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionLabel(String(localized: "캘린더", comment: "Calendar label"), icon: "calendar")

                if !calendarManager.authorizationChecked {
                    ProgressView()
                        .controlSize(.small)
                    Text("로딩 중...", comment: "Loading")
                        .foregroundColor(.secondary)
                        .font(.callout)
                } else if calendarManager.calendars.isEmpty {
                    Text("사용 가능한 캘린더가 없습니다", comment: "No calendars available")
                        .foregroundColor(.secondary)
                        .font(.callout)
                } else {
                    Picker("", selection: $selectedCalendarID) {
                        ForEach(calendarManager.calendars, id: \.calendarIdentifier) { cal in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(cgColor: cal.cgColor))
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                            }
                            .tag(cal.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Re-analyze Section

    /// 다른 프로바이더로 재분석을 제공하는 섹션 (API 키 있는 프로바이더만 활성)
    private var reanalyzeSection: some View {
        VStack(spacing: 6) {
            if isReanalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("재분석 중...", comment: "Re-analyzing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text(currentProviderName.isEmpty ? "추출 완료" : "\(currentProviderName)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    ForEach(reanalyzeProviders, id: \.self) { provider in
                        Button {
                            Task { await performReanalyze(with: provider) }
                        } label: {
                            Text(reanalyzeButtonLabel(provider))
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!hasAPIKey(for: provider))
                        .help(hasAPIKey(for: provider)
                              ? String(localized: "\(provider.displayName)(으)로 재분석", comment: "Re-analyze tooltip")
                              : String(localized: "API 키 필요", comment: "API key required tooltip"))
                    }
                }

                if let error = reanalyzeError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    /// 재분석 가능 프로바이더 (Apple 제외, 현재 사용한 프로바이더 제외 불필요 — 모두 표시)
    private var reanalyzeProviders: [LLMProviderID] {
        [.gemini, .openai, .claude]
    }

    private func reanalyzeButtonLabel(_ provider: LLMProviderID) -> String {
        switch provider {
        case .gemini: "Gemini"
        case .openai: "GPT"
        case .claude: "Claude"
        case .apple: "Apple"
        }
    }

    private func hasAPIKey(for provider: LLMProviderID) -> Bool {
        guard provider != .apple else { return true }
        return KeychainManager.load(key: provider.keychainKey) != nil
    }

    private func performReanalyze(with provider: LLMProviderID) async {
        guard let onReanalyze else { return }

        isReanalyzing = true
        reanalyzeError = nil

        if let newEvent = await onReanalyze(provider) {
            updateFromEvent(newEvent)
            currentProviderName = provider.displayName
        } else {
            reanalyzeError = String(localized: "재분석에 실패했습니다.", comment: "Re-analysis failed")
        }

        isReanalyzing = false
    }

    /// 재분석 결과로 폼 필드 전체 갱신
    private func updateFromEvent(_ newEvent: ScheduleEvent) {
        suppressAutoAdvance = true

        title = newEvent.title ?? title
        isAllDay = newEvent.allDay ?? isAllDay
        location = newEvent.location ?? ""
        notes = newEvent.notes ?? ""

        if let d = newEvent.parsedStartDate() { startDate = d }
        if let d = newEvent.parsedEndDate() { endDate = d }

        if endDate <= startDate {
            endDate = startDate.addingTimeInterval(Double(defaultDurationMinutes) * 60)
        }
        bumpPastDateToTomorrow()
        fixUnreasonableEndDate()
        syncTimeFields()
        loadConflictEvents()

        DispatchQueue.main.async { suppressAutoAdvance = false }
    }

    /// 시작 시간이 이미 지났으면 내일로 보정
    private func bumpPastDateToTomorrow() {
        guard startDate < Date() else { return }
        let cal = Calendar.current
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: startDate) {
            let delta = tomorrow.timeIntervalSince(startDate)
            startDate = tomorrow
            endDate = endDate.addingTimeInterval(delta)
        }
    }

    /// 비합리적 종료시간 보정 (종일이 아닌데 24시간 이상 차이)
    private func fixUnreasonableEndDate() {
        guard !isAllDay else { return }
        let diff = endDate.timeIntervalSince(startDate)
        if diff > 24 * 3600 || diff <= 0 {
            endDate = startDate.addingTimeInterval(Double(defaultDurationMinutes) * 60)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack(spacing: 12) {
            if isRegistered {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("등록 완료!", comment: "Registration complete")
                        .foregroundColor(.green)
                }
                .transition(.opacity)
            }

            Spacer()

            Button {
                onCancelled?()
                onDismiss()
            } label: {
                Text("취소", comment: "Cancel button")
                    .frame(width: 72)
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)

            Button(action: handleRegister) {
                Text("등록", comment: "Register button")
                    .frame(width: 72)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(accentOrange)
            .controlSize(.large)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || calendarManager.calendars.isEmpty)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(accentOrange)
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundColor(.primary)
        }
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 16)
    }

    // MARK: - Time Validation

    /// Format check only — no side effects (for onChange visual feedback)
    private func isValidTimeFormat(_ text: String) -> Bool {
        let raw = text.trimmingCharacters(in: .whitespaces)
        var h = 0, m = 0

        if raw.contains(":") {
            let parts = raw.split(separator: ":")
            guard parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]) else { return false }
            h = hh; m = mm
        } else if raw.count == 4, let val = Int(raw) {
            h = val / 100; m = val % 100
        } else {
            return false
        }

        return h >= 0 && h <= 23 && m >= 0 && m <= 59
    }

    private func validateAndApplyTime(_ text: String, to date: inout Date, base: Date) -> Bool {
        let raw = text.trimmingCharacters(in: .whitespaces)
        var h = 0, m = 0

        if raw.contains(":") {
            let parts = raw.split(separator: ":")
            guard parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]) else { return false }
            h = hh; m = mm
        } else if raw.count == 4, let val = Int(raw) {
            h = val / 100; m = val % 100
        } else if raw.count == 3, let val = Int(raw) {
            h = val / 100; m = val % 100
        } else {
            return false
        }

        guard h >= 0, h <= 23, m >= 0, m <= 59 else { return false }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        if let newDate = cal.date(from: comps) {
            date = newDate
            return true
        }
        return false
    }

    private func syncTimeFields() {
        let cal = Calendar.current
        startTimeText = String(format: "%02d:%02d",
                               cal.component(.hour, from: startDate),
                               cal.component(.minute, from: startDate))
        endTimeText = String(format: "%02d:%02d",
                             cal.component(.hour, from: endDate),
                             cal.component(.minute, from: endDate))
    }

    /// Alias used by onChange handlers
    private func syncTimeTexts() { syncTimeFields() }

    // MARK: - Conflict Events

    private func loadConflictEvents() {
        guard showTimeline else { return }
        existingEvents = calendarManager.fetchEvents(
            for: startDate,
            calendarIDs: conflictCheckCalendarIDs
        )
    }

    // MARK: - Populate

    private func populateFromEvent() {
        title = event.title ?? ""
        isAllDay = event.allDay ?? false
        location = event.location ?? ""
        notes = event.notes ?? ""
        currentProviderName = providerName

        if let d = event.parsedStartDate() { startDate = d }
        if let d = event.parsedEndDate() { endDate = d }

        if endDate <= startDate {
            endDate = startDate.addingTimeInterval(Double(defaultDurationMinutes) * 60)
        }
        bumpPastDateToTomorrow()
        fixUnreasonableEndDate()
        syncTimeFields()
    }

    private func selectDefaultCalendar(from cals: [EKCalendar]) {
        guard !cals.isEmpty else { return }

        // 1. 마지막 사용한 캘린더 매칭
        if let lastName = CalendarManager.loadLastCalendarName(),
           let match = cals.first(where: { $0.title == lastName })
        {
            selectedCalendarID = match.calendarIdentifier
            return
        }

        // 매칭 실패 → 저장된 이름이 삭제된 캘린더이므로 정리
        if CalendarManager.loadLastCalendarName() != nil {
            CalendarManager.clearLastCalendarName()
        }

        // 2. 시스템 기본 캘린더
        if let def = calendarManager.store.defaultCalendarForNewEvents,
           cals.contains(where: { $0.calendarIdentifier == def.calendarIdentifier })
        {
            selectedCalendarID = def.calendarIdentifier
            return
        }

        // 3. 목록의 첫 번째
        selectedCalendarID = cals.first?.calendarIdentifier ?? ""
    }

    /// 선택된 캘린더가 여전히 유효한지 확인, 아니면 기본으로 재선택
    private func validateSelectedCalendar() {
        let cals = calendarManager.calendars
        if !cals.contains(where: { $0.calendarIdentifier == selectedCalendarID }) {
            selectDefaultCalendar(from: cals)
        }
    }

    // MARK: - Actions

    private func handleRegister() {
        if !isAllDay {
            startTimeValid = validateAndApplyTime(startTimeText, to: &startDate, base: startDate)
            endTimeValid = validateAndApplyTime(endTimeText, to: &endDate, base: endDate)
            guard startTimeValid, endTimeValid else {
                errorText = String(localized: "시간 형식이 올바르지 않습니다. (HH:MM)", comment: "Time format error")
                showError = true
                return
            }
            guard endDate > startDate else {
                errorText = String(localized: "종료 시간이 시작 시간보다 이후여야 합니다.", comment: "End before start error")
                showError = true
                return
            }
        }

        guard let calendar = calendarManager.calendars.first(where: {
            $0.calendarIdentifier == selectedCalendarID
        }) else {
            errorText = String(localized: "캘린더를 선택해 주세요.", comment: "Select calendar error")
            showError = true
            return
        }

        do {
            try calendarManager.createEvent(
                title: title.trimmingCharacters(in: .whitespaces),
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                location: location,
                notes: notes,
                calendar: calendar
            )
            CalendarManager.saveLastCalendarName(calendar.title)
            let dateStr = event.startDate ?? ""
            onRegistered?(title.trimmingCharacters(in: .whitespaces), dateStr)

            withAnimation { isRegistered = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        } catch {
            errorText = String(localized: "일정 등록 실패: \(error.localizedDescription)", comment: "Registration failed")
            showError = true
        }
    }
}
