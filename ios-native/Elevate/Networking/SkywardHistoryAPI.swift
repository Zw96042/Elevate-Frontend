import Foundation
import OSLog

/// One course row from academic history (and, after combining, the current gradebook).
struct HistoryCourse: Codable, Hashable {
    var courseName: String?
    var terms: String = ""
    var finalGrade: String = ""
    var sm1: String?, sm2: String?
    var pr1: String?, pr2: String?, pr3: String?, pr4: String?
    var pr5: String?, pr6: String?, pr7: String?, pr8: String?
    var rc1: String?, rc2: String?, rc3: String?, rc4: String?
    var ex1: String?, ex2: String?

    // Filled in from the live gradebook for current-year courses.
    var courseId: Int?
    var instructor: String?
    var period: Int?
    var time: String?
    var stuId: String?
    var corNumId: String?
    var section: String?
    var gbId: String?

    mutating func setBucketField(_ field: String, value: String) {
        switch field {
        case "pr1": pr1 = value; case "pr2": pr2 = value; case "pr3": pr3 = value; case "pr4": pr4 = value
        case "pr5": pr5 = value; case "pr6": pr6 = value; case "pr7": pr7 = value; case "pr8": pr8 = value
        case "rc1": rc1 = value; case "rc2": rc2 = value; case "rc3": rc3 = value; case "rc4": rc4 = value
        case "sm1": sm1 = value; case "sm2": sm2 = value
        default: break
        }
    }
}

struct AcademicYear: Codable, Hashable {
    var grade: Int?
    var courses: [String: HistoryCourse]
}

/// Keyed by "2024-2025"-style year strings.
typealias AcademicHistory = [String: AcademicYear]

struct GradebookCourse {
    var course: Int
    var courseName: String
    var instructor: String
    var period: Int
    var time: String?
    var scores: [(bucket: String, score: Double)]
    var stuId: String?
    var corNumId: Int?
    var section: String?
    var gbId: String?
}

enum SkywardHistoryAPI {
    private static let logger = Logger(subsystem: "com.zacharywilson.elevate", category: "SkywardHistory")

    // MARK: - Fetching

    static func fetchCombinedAcademicData(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> AcademicHistory {
        async let historyTask = fetchAcademicHistory(baseUrl: baseUrl, sessionCodes: sessionCodes)
        async let gradebookTask = fetchGradebookHTML(baseUrl: baseUrl, sessionCodes: sessionCodes)

        let history = try await historyTask
        let gradebookHTML = try await gradebookTask
        let gradebookCourses = try parseGradebookHTML(gradebookHTML)
        let gradeLevel = inferGradeLevel(from: gradebookHTML)
        #if DEBUG
        logger.debug("Parsed current gradebook courses=\(gradebookCourses.count, privacy: .public) inferredGrade=\(gradeLevel ?? -1, privacy: .public)")
        #endif
        return combine(history: history, gradebook: gradebookCourses, fallbackGrade: gradeLevel)
    }

    static func fetchAcademicHistory(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> AcademicHistory {
        guard let url = URL(string: baseUrl + "sfacademichistory001.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let fields: [(String, String)] = [
            ("dwd", sessionCodes.dwd),
            ("wfaacl", sessionCodes.wfaacl),
            ("encses", sessionCodes.encses),
        ]
        let html = try await SkywardHTTP.post(url: url, fields: fields)
        try SkywardHTTP.checkSessionExpired(html)
        if isVerifiedEmptyAcademicHistoryPage(html) {
            #if DEBUG
            logger.debug("Academic-history page contains no historical grid; continuing with current gradebook")
            #endif
            return [:]
        }

        let gridObjects = try parseGridObjects(html: html, pattern: #"sff\.sv\('sf_gridObjects',\s*\$\.extend\([^,]+,\s*(\{[\s\S]*?\})\)\);"#)
        return try condenseAcademicHistory(gridObjects)
    }

    static func isVerifiedEmptyAcademicHistoryPage(_ html: String) -> Bool {
        guard !html.contains("sf_gridObjects") else { return false }
        let root = MiniHTML.parse(html)
        let title = root.querySelector("title")?.text ?? ""
        guard title.localizedCaseInsensitiveContains("Academic History") else { return false }
        let pageText = root.querySelector("body")?.text ?? root.text
        return pageText.range(
            of: #"\bno\s+(?:academic\s+history\s+)?records?(?:\s+(?:found|available|to\s+display))?\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func fetchGradebookHTML(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> String {
        guard let url = URL(string: baseUrl + "sfgradebook001.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let html = try await SkywardHTTP.post(url: url, fields: SkywardHTTP.sessionFields(sessionCodes))
        try SkywardHTTP.checkSessionExpired(html)
        return html
    }

    // MARK: - sf_gridObjects extraction (bounded data-only parser)

    static func parseGridObjects(html: String, pattern: String) throws -> [String: Any] {
        let root = MiniHTML.parse(html)
        if root.querySelector("title")?.text.contains("Family Access") == true, html.count < 5000 {
            throw SkywardError.sessionExpired
        }

        let scripts = root.querySelectorAll("script")
        for script in scripts {
            let content = script.text
            guard content.contains("sf_gridObjects") else { continue }
            guard let m = SkywardGradesAPI.firstMatch(in: content, pattern: pattern) else { continue }
            guard let object = try JavaScriptLiteralParser.parse(m[1]) as? [String: Any] else {
                throw SkywardError.invalidResponse("failed to parse grid objects")
            }
            return object
        }
        #if DEBUG
        let title = root.querySelector("title")?.text ?? ""
        logger.error("Grid extraction failed title=\(title, privacy: .public) scripts=\(scripts.count, privacy: .public) containsMarker=\(html.contains("sf_gridObjects"), privacy: .public)")
        #endif
        throw SkywardError.invalidResponse("no academic history data found")
    }

    // MARK: - Academic history condensing

    static func condenseAcademicHistory(_ gridObjects: [String: Any]) throws -> AcademicHistory {
        let targetPairs = gridObjects
            .filter { $0.key.range(of: #"gradeGrid_\d+_\d+_\d+"#, options: .regularExpression) != nil }
        guard !targetPairs.isEmpty else {
            throw SkywardError.invalidResponse("academic-history grid not found")
        }

        var academicYears: AcademicHistory = [:]

        for (_, value) in targetPairs {
            guard let grid = value as? [String: Any],
                  let tb = grid["tb"] as? [String: Any],
                  let rows = tb["r"] as? [[String: Any]] else {
                throw SkywardError.invalidResponse("academic-history grid is incomplete")
            }

            struct YearSection {
                var begin: String
                var end: String
                var grade: Int
                var rows: [[String: Any]]
            }
            var sections: [YearSection] = []
            var current: YearSection? = nil

            for row in rows {
                guard let cells = row["c"] as? [[String: Any]], !cells.isEmpty else { continue }
                let firstHTML = cells[0]["h"] as? String ?? ""
                let yearText = MiniHTML.parse(firstHTML).text
                if let m = SkywardGradesAPI.firstMatch(in: yearText, pattern: #"(\d{4})\s*-\s*(\d{4}).*Grade\s+(\d+)"#) {
                    guard let begin = Int(m[1]), let end = Int(m[2]),
                          let grade = Int(m[3]), end == begin + 1, (1...12).contains(grade) else {
                        throw SkywardError.invalidResponse("academic-history year header is invalid")
                    }
                    if let current { sections.append(current) }
                    current = YearSection(begin: m[1], end: m[2], grade: grade, rows: [])
                } else if current != nil {
                    current?.rows.append(row)
                }
            }
            if let current { sections.append(current) }
            if !rows.isEmpty, sections.isEmpty {
                throw SkywardError.invalidResponse("academic-history grid has unrecognized populated rows")
            }

            for section in sections {
                var courses: [String: HistoryCourse] = [:]
                var nameCounts: [String: Int] = [:]
                var validCourseRows = 0
                var malformedRows = 0

                for row in section.rows {
                    if isKnownEmptyHistoryRow(row) { continue }
                    guard let parsed = parseCourseRow(row) else {
                        malformedRows += 1
                        continue
                    }
                    guard isValidCourse(name: parsed.name) else { continue }
                    validCourseRows += 1
                    // Alt courses (non-linked rows, e.g. middle-school credit) are
                    // excluded from year data, matching the unified-data transform.
                    if parsed.isAlt { continue }

                    var key = parsed.name
                    if courses[key] != nil || nameCounts[parsed.name] ?? 0 > 0 {
                        let count = (nameCounts[parsed.name] ?? 1) + 1
                        nameCounts[parsed.name] = count
                        key = "\(parsed.name)_\(count)"
                    } else {
                        nameCounts[parsed.name] = 1
                    }
                    courses[key] = parsed.course
                }

                if !section.rows.isEmpty, validCourseRows == 0, malformedRows > 0 {
                    throw SkywardError.invalidResponse("academic-history grid has malformed populated rows")
                }

                // Transcripts can carry pre-high-school credit. Validate those
                // sections but omit them from Elevate's grade 9-12 model.
                if section.grade < 9 { continue }

                if !courses.isEmpty || section.rows.count > 1 {
                    academicYears["\(section.begin)-\(section.end)"] = AcademicYear(grade: section.grade, courses: courses)
                }
            }
        }
        return academicYears
    }

    private static func parseCourseRow(_ row: [String: Any]) -> (name: String, isAlt: Bool, course: HistoryCourse)? {
        guard let cells = row["c"] as? [[String: Any]], cells.count >= 18,
              cells.allSatisfy({ $0["h"] is String }) else { return nil }
        let columns: [String] = cells.map { cell in
            MiniHTML.parse(cell["h"] as? String ?? "").text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func col(_ i: Int) -> String { columns.indices.contains(i) ? columns[i] : "" }

        let firstHTML = cells[0]["h"] as? String ?? ""
        let isAlt = !(firstHTML.contains("<a ") || firstHTML.contains("<a>"))

        let name = col(0)
        guard !name.isEmpty else { return nil }

        var course = HistoryCourse()
        course.courseName = name
        course.terms = col(1)
        course.pr1 = col(2); course.pr2 = col(3); course.rc1 = col(4)
        course.pr3 = col(5); course.pr4 = col(6); course.rc2 = col(7)
        course.ex1 = col(8); course.sm1 = col(9).isEmpty ? nil : col(9)
        course.pr5 = col(10); course.pr6 = col(11); course.rc3 = col(12)
        course.pr7 = col(13); course.pr8 = col(14); course.rc4 = col(15)
        course.ex2 = col(16); course.sm2 = col(17).isEmpty ? nil : col(17)
        course.finalGrade = course.sm2 ?? course.sm1
            ?? [course.rc4, course.rc3, course.rc2, course.rc1].compactMap { $0 }.first { !$0.isEmpty }
            ?? ""
        return (name, isAlt, course)
    }

    private static func isKnownEmptyHistoryRow(_ row: [String: Any]) -> Bool {
        guard let cells = row["c"] as? [[String: Any]] else { return false }
        let text = cells.map { MiniHTML.parse($0["h"] as? String ?? "").text }.joined(separator: " ")
        return text.range(
            of: #"\bno\s+(?:academic\s+history\s+)?records?\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isValidCourse(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return false }
        let excludePatterns = [
            #"^Class$"#, #"^Terms$"#, #"^\d{4}\s*-\s*\d{4}.*Grade"#,
            #"^PR\d+$"#, #"^RC\d+$"#, #"^EX\d+$"#, #"^SM\d+$"#, #"^LUNCH"#,
        ]
        return !excludePatterns.contains { pattern in
            trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - Current gradebook grid

    static func parseGradebookHTML(_ html: String) throws -> [GradebookCourse] {
        let gridObjects = try parseGridObjects(
            html: html,
            pattern: #"\$\.extend\(\(sff\.getValue\('sf_gridObjects'\) \|\| \{\}\), ([\s\S]*)\)\);"#
        )

        #if DEBUG
        let gridKeys = gridObjects.keys.map {
            $0.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
        }.sorted().joined(separator: ",")
        logger.debug("Current gradebook grid keys=\(gridKeys, privacy: .public)")
        #endif

        guard let targetPair = gridObjects.first(where: { $0.key.range(of: #"stuGradesGrid_\d+_\d+"#, options: .regularExpression) != nil }),
              let gridData = targetPair.value as? [String: Any],
              let tb = gridData["tb"] as? [String: Any],
              let rows = tb["r"] as? [[String: Any]] else {
            #if DEBUG
            logger.error("Current gradebook response has no compatible stuGradesGrid")
            #endif
            throw SkywardError.invalidResponse("current gradebook grid is missing or incomplete")
        }

        // Course details (name, instructor, period, ids) from classDesc_ tables.
        struct CourseDetails {
            var courseName = "", instructor = ""
            var period: Int? = nil
            var time: String? = nil
            var stuId = "", corNumId = 0, section = ""
        }
        var detailsById: [Int: CourseDetails] = [:]
        let root = MiniHTML.parse(html)
        for table in root.querySelectorAll("table[id*=\"classDesc_\"]") {
            guard let idMatch = SkywardGradesAPI.firstMatch(in: table.id, pattern: #"classDesc_(\d+)_(\d+)_0_(\d+)"#) else { continue }
            var details = CourseDetails()
            details.stuId = idMatch[1]
            details.corNumId = Int(idMatch[2]) ?? 0
            details.section = idMatch[3]
            details.courseName = table.querySelector("span.bld.classDesc a")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            details.instructor = table.querySelector("tr:last-child td a")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let periodCell = table.querySelector("tr:nth-child(2) td") {
                if let m = SkywardGradesAPI.firstMatch(in: periodCell.text, pattern: #"Period\s*(\d+)"#) {
                    details.period = Int(m[1])
                }
                if let timeSpan = periodCell.querySelector("span.fXs.fWn"),
                   let m = SkywardGradesAPI.firstMatch(in: timeSpan.text, pattern: #"\(([^)]+)\)"#) {
                    details.time = m[1]
                }
            }
            detailsById[details.corNumId] = details
        }

        #if DEBUG
        logger.debug("Current gradebook rows=\(rows.count, privacy: .public) classDescriptions=\(detailsById.count, privacy: .public)")
        #endif

        var courses: [GradebookCourse] = []
        var recognizedCourseRows = 0
        for row in rows {
            guard let cells = row["c"] as? [[String: Any]], !cells.isEmpty,
                  cells[0]["cId"] != nil else { continue }
            recognizedCourseRows += 1

            var courseNumber: Int? = nil
            var gbId: String? = nil
            var scores: [(String, Double)] = []

            for cell in cells {
                guard let cellHTML = cell["h"] as? String else { continue }
                let cellRoot = MiniHTML.parse(cellHTML)
                guard let gradeElement = cellRoot.querySelector("[data-cni]") ?? cellRoot.querySelector("a") else { continue }
                guard let cni = gradeElement.attribute("data-cni"), let course = Int(cni), course != 0 else { continue }
                if gbId == nil, let gid = gradeElement.attribute("data-gid") {
                    gbId = gid
                }
                guard let bucket = gradeElement.attribute("data-bkt") else { continue }
                courseNumber = course
                let scoreText = gradeElement.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let score = AcademicScoreValue.finiteDouble(scoreText) {
                    scores.append((bucket, score))
                }
            }

            guard let courseNumber else {
                throw SkywardError.invalidResponse("current gradebook course row is incomplete")
            }
            let details = detailsById[courseNumber]
            courses.append(GradebookCourse(
                course: courseNumber,
                courseName: details?.courseName ?? "Unknown Course",
                instructor: details?.instructor ?? "Unknown Instructor",
                period: details?.period ?? 0,
                time: details?.time,
                scores: scores,
                stuId: details?.stuId,
                corNumId: details?.corNumId,
                section: details?.section,
                gbId: gbId
            ))
        }
        if !rows.isEmpty, recognizedCourseRows == 0 {
            throw SkywardError.invalidResponse("current gradebook has unrecognized populated rows")
        }
        #if DEBUG
        logger.debug("Current gradebook parsed course rows=\(courses.count, privacy: .public)")
        #endif
        return courses
    }

    // MARK: - Combining

    static func inferGradeLevel(from html: String) -> Int? {
        let text = MiniHTML.parse(html).text
        let patterns = [#"\bGrade\s*(9|10|11|12)\b"#, #"\b(9|10|11|12)(?:st|nd|rd|th)\s+Grade\b"#]
        for pattern in patterns {
            if let match = SkywardGradesAPI.firstMatch(in: text, pattern: pattern, caseInsensitive: true),
               let grade = Int(match[1]) {
                return grade
            }
        }
        return nil
    }

    static let bucketToField: [String: String] = [
        "TERM 1": "pr1", "TERM 2": "pr2", "TERM 3": "rc1",
        "TERM 4": "pr3", "TERM 5": "pr4", "TERM 6": "rc2",
        "TERM 7": "pr5", "TERM 8": "pr6", "TERM 9": "rc3",
        "TERM 10": "pr7", "TERM 11": "pr8", "TERM 12": "rc4",
        "SEM 1": "sm1", "SEM 2": "sm2",
    ]

    static func combine(
        history: AcademicHistory,
        gradebook: [GradebookCourse],
        fallbackGrade: Int? = nil
    ) -> AcademicHistory {
        guard !gradebook.isEmpty else { return history }
        let latestYear: String
        var yearData: AcademicYear
        if let existingYear = history.keys.sorted().last, let existingData = history[existingYear] {
            if let fallbackGrade, existingData.grade != fallbackGrade {
                latestYear = nextAcademicYearKey(after: existingYear, existingKeys: Set(history.keys))
                yearData = AcademicYear(grade: fallbackGrade, courses: [:])
            } else {
                latestYear = existingYear
                yearData = existingData
            }
        } else {
            latestYear = "current"
            yearData = AcademicYear(grade: fallbackGrade, courses: [:])
        }

        let existingCourses = yearData.courses
        var mergedCourses = existingCourses
        var claimedExistingKeys: Set<String> = []

        for gbCourse in gradebook {
            let matchedKey = existingCourses.first { key, course in
                guard !claimedExistingKeys.contains(key) else { return false }
                if let liveCourseNumber = gbCourse.corNumId,
                   course.corNumId == String(liveCourseNumber),
                   course.section == gbCourse.section {
                    return true
                }
                let existingName = course.courseName ?? key
                return normalizedCourseName(existingName) == normalizedCourseName(gbCourse.courseName)
            }?.key
            if let matchedKey {
                claimedExistingKeys.insert(matchedKey)
            }
            var course = matchedKey.flatMap { existingCourses[$0] } ?? {
                var fresh = HistoryCourse()
                fresh.terms = "1 - 4"
                return fresh
            }()

            course.courseName = gbCourse.courseName
            course.courseId = gbCourse.course
            course.instructor = gbCourse.instructor
            course.period = gbCourse.period
            if let time = gbCourse.time { course.time = time }
            course.stuId = gbCourse.stuId
            course.corNumId = gbCourse.corNumId.map(String.init)
            course.section = gbCourse.section
            course.gbId = gbCourse.gbId

            for (bucket, score) in gbCourse.scores {
                if let field = bucketToField[bucket], field != "ex1", field != "ex2" {
                    course.setBucketField(field, value: formatScore(score))
                }
            }

            let storageKey = matchedKey ?? uniqueStorageKey(
                for: gbCourse.courseName,
                existingKeys: Set(mergedCourses.keys)
            )
            mergedCourses[storageKey] = course
        }

        yearData.courses = mergedCourses
        var updated = history
        updated[latestYear] = yearData
        return updated
    }

    private static func nextAcademicYearKey(
        after latestYear: String,
        existingKeys: Set<String>
    ) -> String {
        let years = latestYear.split(separator: "-").compactMap { Int($0) }
        guard years.count == 2 else {
            var suffix = 1
            var candidate = "current"
            while existingKeys.contains(candidate) {
                suffix += 1
                candidate = "current-\(suffix)"
            }
            return candidate
        }

        var start = years[1]
        var candidate = "\(start)-\(start + 1)"
        while existingKeys.contains(candidate) {
            start += 1
            candidate = "\(start)-\(start + 1)"
        }
        return candidate
    }

    static func formatScore(_ score: Double) -> String {
        guard score.isFinite, abs(score) <= AcademicScoreValue.magnitudeLimit else { return "" }
        return score == score.rounded() ? String(Int(score)) : String(score)
    }

    private static func normalizedCourseName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"_\d+$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    }

    private static func uniqueStorageKey(for courseName: String, existingKeys: Set<String>) -> String {
        guard existingKeys.contains(courseName) else { return courseName }
        var suffix = 2
        while existingKeys.contains("\(courseName)_\(suffix)") {
            suffix += 1
        }
        return "\(courseName)_\(suffix)"
    }
}
