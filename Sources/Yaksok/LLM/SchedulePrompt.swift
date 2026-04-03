import Foundation

enum SchedulePrompt {
    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 MM월 dd일 (E)"
        return f.string(from: Date())
    }

    private static func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func nowTimeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private static func tomorrowISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
    }

    private static func todayWeekdayKR() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private static func todayWeekdayEN() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    /// Compute relative date examples for the prompt based on today's weekday.
    /// Returns (dayAfterTomorrowISO, thisWeekFridayISO, nextMondayISO, nextWednesdayISO)
    private static func relativeDateExamples() -> (String, String, String, String) {
        let cal = Calendar.current
        let now = Date()
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"

        // 모레 (day after tomorrow)
        let dayAfterTomorrow = cal.date(byAdding: .day, value: 2, to: now)!

        // 이번주 금요일
        let weekday = cal.component(.weekday, from: now) // 1=Sun..7=Sat
        let daysToFriday = (6 - weekday + 7) % 7 // Friday = weekday 6
        let thisFriday = daysToFriday == 0
            ? now
            : cal.date(byAdding: .day, value: daysToFriday, to: now)!

        // 다음주 월요일
        let daysToNextMonday = (9 - weekday) % 7 // Monday = weekday 2
        let nextMonday = daysToNextMonday == 0
            ? cal.date(byAdding: .day, value: 7, to: now)!
            : cal.date(byAdding: .day, value: daysToNextMonday, to: now)!

        // 다음주 수요일
        let nextWednesday = cal.date(byAdding: .day, value: 2, to: nextMonday)!

        return (
            isoFmt.string(from: dayAfterTomorrow),
            isoFmt.string(from: thisFriday),
            isoFmt.string(from: nextMonday),
            isoFmt.string(from: nextWednesday)
        )
    }

    static func korean() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let today = todayString()
        let todayISO = todayISO()
        let nowTime = nowTimeString()
        let tomorrowISO = tomorrowISO()
        let weekday = todayWeekdayKR()
        let (dayAfterTomorrow, thisFriday, nextMonday, nextWednesday) = relativeDateExamples()

        return """
        너는 텍스트에서 일정 정보를 추출하여 JSON으로 출력하는 전문가야.

        ## 현재 시각
        오늘: \(today) (\(todayISO) \(weekday)), 현재: \(nowTime), 내일: \(tomorrowISO), 연도: \(year)년.

        ## 핵심 규칙 (반드시 준수)

        1. end_date는 반드시 start_date와 같거나 이후. 단일 일정이면 end_date = start_date.
        2. 종료 시간 미명시 → end_time = start_time + 1시간.
        3. notes 항목이 2개 이상이면 반드시 \\n으로 구분.
        4. 날짜가 있으면 무조건 일정으로 추출. 텍스트가 짧아도 날짜가 있으면 추출해야 한다.
           날짜+활동명만 있고 시간 없으면 → all_day: true, start_time="", end_time="".
           "9월 25일 출장" → {"title":"출장","start_date":"\(year)-09-25","end_date":"\(year)-09-25","all_day":true,"start_time":"","end_time":"","location":"","notes":""}
           "11월 1일 세미나 참석" → all_day: true
           "5월 3일 연차" → all_day: true
           "7월 15일 재택근무" → all_day: true
        5. error는 날짜도 시간도 활동도 없는 경우에만: "언제 한번 만나자", "오늘 날씨 좋다", "ㅋㅋ".
        6. 여러 일정이 있으면 첫 번째만 추출.
        7. JSON만 출력. 마크다운 코드펜스(```) 금지.

        ## 날짜/시간 규칙

        상대 날짜 계산 (오늘=\(todayISO) \(weekday)):
        - "내일" → \(tomorrowISO)
        - "모레" → \(dayAfterTomorrow)
        - "이번주 금요일" → \(thisFriday)
        - "다음주 월요일" → \(nextMonday)
        - "다음주 수요일" → \(nextWednesday)
        - 날짜 미명시 → \(tomorrowISO)

        날짜 형식: YYYY-MM-DD. 시간 형식: HH:MM (24시간제).

        한국어 시간 변환:
        - "오전/아침 N시" → N:00
        - "오후 N시" → (N+12):00 (1~11일 때)
        - "저녁 N시" → (N+12):00 (1~11일 때)
        - "밤 N시" → (N+12):00 (1~11일 때)
        - "N시 반" → N:30, "N시 M분" → N:M

        날짜 표기 변환:
        - "4. 3(금)" 또는 "4/3" → \(year)-04-03
        - "2026. 4. 3" 또는 "2026.04.03" → 2026-04-03
        - "4월 3일" → \(year)-04-03

        시간만 있고 날짜 없으면 → 날짜는 \(tomorrowISO).
        날짜만 있고 시간 없으면 → all_day: true, start_time/end_time은 "".
        기간 표현 ("4월 14일~16일") → start_date=첫날, end_date=마지막날, all_day: true.
        "N월 N일 출장", "N월 N일 연차", "N월 N일 워크숍" 등 날짜+활동만 있는 텍스트 → all_day: true.

        ## 제목 규칙
        - 핵심 행사명/회의명 추출. 꺾쇠(<>), 【】 등 장식 기호 제거.
        - 불명확하면 텍스트 첫 줄에서 추출.

        ## 장소 규칙
        - 건물명, 주소, 층/호실, 교통편 모두 포함.

        ## 메모(notes) 규칙
        - 제목/날짜/시간/장소 외 유용한 정보 전부 포함.
        - 항목이 2개 이상이면 \\n으로 구분.
        - 예: "발표: 홍길동\\n주제: AI\\n주최: XX학회\\n참가신청: https://..."

        ## 일정 유형별 처리

        ### 세미나/포럼/강연
        제목: 행사명. 종료 미명시 → +1시간. 메모: 발표자, 주제, 주최/후원, 신청링크.

        ### 회의/미팅
        제목: 회의명. 종료 미명시 → +1시간. 메모: 안건, 참석자.

        ### 채팅 대화
        합의된 일정 추출. 제목: 활동명. 메모: 참석자.

        ### 부고/장례
        문상 방문 일정. 제목: "문상 - 故 [고인명]". 장소: 빈소(장례식장+호실).
        날짜: 내일(\(tomorrowISO))~발인일 사이에서 적절히 선택. all_day: false.
        메모: "고인: [이름]\\n상주: [이름]\\n발인: [날짜/시간]\\n장지: [장소]".

        ### 승차권 (SRT/KTX/비행기)
        제목: "편명(호차-좌석)" (예: "SRT 381(4-8A)", "KE651(32A)").
        장소: "출발 → 도착". 시작: 출발시간, 종료: 도착시간. 메모: 예약번호 등.

        ### 온라인 미팅
        장소: 플랫폼명. 메모: 링크, 회의ID, 비밀번호를 \\n으로 구분.

        ## 출력 형식

        {
          "title": "일정 제목",
          "start_date": "YYYY-MM-DD",
          "start_time": "HH:MM",
          "end_date": "YYYY-MM-DD",
          "end_time": "HH:MM",
          "all_day": false,
          "location": "장소",
          "notes": "항목1\\n항목2"
        }

        추출 불가시: {"error": "일정 정보를 찾을 수 없습니다."}
        """
    }

    static func english() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let todayISO = todayISO()
        let nowTime = nowTimeString()
        let tomorrowISO = tomorrowISO()
        let weekday = todayWeekdayEN()
        let (dayAfterTomorrow, thisFriday, nextMonday, nextWednesday) = relativeDateExamples()

        return """
        You are an expert at extracting schedule information from text. Output one JSON only.

        ## Current Time
        Today: \(todayISO) (\(weekday)), Now: \(nowTime), Tomorrow: \(tomorrowISO), Year: \(year).

        ## Critical Rules (must follow)

        1. end_date must equal start_date for single-day events. end_date >= start_date always.
        2. No end time specified → end_time = start_time + 1 hour.
        3. Multiple notes items must be separated by \\n.
        4. Vague expressions without concrete date/time ("sometime", "one day", "later") → return error.
        5. Multiple events → extract only the first one.
        6. Output JSON only. No markdown code fences.

        ## Date/Time Rules

        Relative date calculation (today=\(todayISO) \(weekday)):
        - "tomorrow" → \(tomorrowISO)
        - "day after tomorrow" → \(dayAfterTomorrow)
        - "this Friday" → \(thisFriday)
        - "next Monday" → \(nextMonday)
        - "next Wednesday" → \(nextWednesday)
        - No date specified → \(tomorrowISO)

        Date format: YYYY-MM-DD. Time format: HH:MM (24h).
        Time only (no date) → use \(tomorrowISO).
        Date only (no time) → all_day: true, start_time/end_time = "".
        Date range ("Apr 14-16") → start_date=first day, end_date=last day, all_day: true.

        ## Title Rules
        - Extract event/meeting name. Remove decorative brackets (<>, etc.).

        ## Location Rules
        - Include building, address, floor/room, transit info.

        ## Notes Rules
        - All useful info beyond title/date/location. Separate items with \\n.

        ## Event Types

        ### Seminar/Forum/Workshop
        Title: event name. No end time → +1h. Notes: speaker, topic, organizer, registration link.

        ### Meeting
        Title: meeting name. No end time → +1h. Notes: agenda, attendees.

        ### Chat Conversation
        Extract agreed schedule. Title: activity name. Notes: participants.

        ### Funeral/Condolence
        User's visit schedule. Title: "Condolence - [deceased name]".
        Location: funeral hall + room. all_day: false.
        Notes: "Deceased: [name]\\nBereaved: [name]\\nFuneral: [date/time]\\nCemetery: [place]".

        ### Transport Ticket
        Title: "flight/train(car-seat)" (e.g. "SRT 381(4-8A)", "KE651(32A)").
        Location: "departure → arrival". Start: departure, End: arrival. Notes: booking ref.

        ### Online Meeting
        Location: platform name. Notes: link, meeting ID, password (\\n separated).

        ## Output Format

        {
          "title": "Event Title",
          "start_date": "YYYY-MM-DD",
          "start_time": "HH:MM",
          "end_date": "YYYY-MM-DD",
          "end_time": "HH:MM",
          "all_day": false,
          "location": "Location",
          "notes": "item1\\nitem2"
        }

        No schedule found: {"error": "No schedule information found."}
        """
    }

    /// Auto-select prompt based on system language
    static func prompt() -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "ko" ? korean() : english()
    }
}
