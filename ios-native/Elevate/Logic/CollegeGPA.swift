import Foundation

struct CollegeGPAResult {
    var profile: CollegeProfile
    var records: [GPAConversionRecord]
    var skipped: [GPAConversionSkippedRecord]
    var calculationNotes: [String] = []
    /// Retained for explanation, never silently included as academic core.
    var omittedRecords: [GPAConversionRecord] = []
    var unavailableReason: String? = nil
    var value: Double? {
        guard unavailableReason == nil, !records.isEmpty else { return nil }
        return records.map(\.points).reduce(0, +) / Double(records.count)
    }
    var standing: CollegeGPAStanding? { value.flatMap { CollegeGPAStanding.compare($0, profile: profile) } }
    /// A weighted result must never be described as a perfect unweighted GPA
    /// without separately checking its underlying completed semester grades.
    var unweightedValue: Double? {
        guard unavailableReason == nil, !records.isEmpty else { return nil }
        let points = records.compactMap { GPAConversionPolicy.unweighted4Point.points(for: $0.percentage, level: .regular) }
        guard points.count == records.count else { return nil }
        return points.reduce(0, +) / Double(points.count)
    }
    /// Never display 3.999 as 4.00 beside a different GPA band.
    var displayValue: String {
        guard let value else { return "—" }
        var decimal = Decimal(value)
        var truncated = Decimal()
        NSDecimalRound(&truncated, &decimal, 2, .down)
        return String(format: "%.2f", NSDecimalNumber(decimal: truncated).doubleValue)
    }
}

struct CollegeGPAStanding: Equatable {
    var title: String
    var detail: String
    var bandLabel: String? = nil
    /// Legacy UI compatibility. A cohort histogram cannot establish a student's rank.
    var higherBandPercent: Double? { nil }
    /// The share of the published reporting cohort in one band, not a percentile.
    var sameBandPercent: Double? = nil
    var cohortContext: String? = nil

    static func compare(_ value: Double, profile: CollegeProfile) -> Self? {
        guard value.isFinite, value >= 0, value <= profile.method.maximum else { return nil }
        let weighted = !profile.method.isUnweighted
        let perfectUnweighted = !weighted && value == 4
        var standing = Self(
            title: perfectUnweighted ? "Highest possible unweighted GPA" : weighted ? (profile.method == .ucFullyWeighted ? "Your fully weighted GPA" : "Your weighted GPA") : "Your unweighted GPA",
            detail: perfectUnweighted
                ? "All A grades in the completed semesters used for this estimate. A 4.0 is the highest possible GPA on this unweighted scale. Course selection and college policies may differ."
                : weighted
                    ? "Your estimate includes the published course-level bonuses. Its weighted value does not establish your unweighted GPA. Course eligibility and college policies may differ."
                    : "Your estimate is on a 4.0 unweighted scale. Course selection and college policies may differ.")
        // A published weighted cohort cannot be compared to a generic unweighted
        // conversion, even when a few of its values happen to fall below 4.0.
        guard !(profile.publishedGPAScale == .weighted && !weighted),
              !(profile.publishedGPAScale == .unweighted && weighted) else { return standing }
        guard profile.reportedMean.map({ $0.isFinite && (0...profile.method.maximum).contains($0) }) ?? true,
              profile.reportingPercent.map({ $0.isFinite && (0...100).contains($0) }) ?? true else { return standing }
        if let quartiles = profile.quartiles {
            guard quartiles.lower.isFinite, quartiles.upper.isFinite,
                  quartiles.lower >= 0, quartiles.lower <= quartiles.upper,
                  quartiles.upper <= profile.method.maximum,
                  quartiles.median.map({ $0.isFinite && (quartiles.lower...quartiles.upper).contains($0) }) ?? true else { return standing }
            standing.cohortContext = "\(profile.cohort), \(profile.population.sentenceDescription): the published middle 50% was \(String(format: "%.2f", quartiles.lower))–\(String(format: "%.2f", quartiles.upper)). This describes a past class, not your individual percentile or admission chances."
            return standing
        }
        guard !profile.bands.isEmpty,
              profile.bands.allSatisfy({ $0.percent.isFinite && (0...100).contains($0.percent) && $0.minimum.isFinite
                  && (0...profile.method.maximum).contains($0.minimum)
                  && ($0.maximum == nil ? $0.minimum == profile.method.maximum : ($0.maximum!.isFinite && $0.maximum! > $0.minimum && $0.maximum! <= profile.method.maximum)) }),
              abs(profile.bands.map(\.percent).reduce(0, +) - 100) <= 0.05,
              profile.bands.filter({ $0.contains(value) }).count == 1,
              let band = profile.bands.first(where: { $0.contains(value) }) else { return standing }
        let share = percent(band.percent)
        standing.bandLabel = band.label
        standing.sameBandPercent = band.percent
        standing.cohortContext = "\(share)% of \(profile.cohort) \(profile.population.sentenceDescription) were in the published \(band.label) GPA band. This is the share of that reporting cohort, not your individual percentile. Reported course selection, credits and weighting may differ from this estimate."
        return standing
    }
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum CollegeGPACalculator {
    static func calculate(profile: CollegeProfile, courses: [UnifiedCourseData],
                          manualClassesByYear: [Int: [ManualClass]] = [:], asOf: Date = Date()) -> CollegeGPAResult {
        let report = GPAConversionCalculator.calculate(courses: courses, manualClassesByYear: manualClassesByYear,
            gradeYears: profile.method.gradeYears, policy: .unweighted4Point, completedOnly: true, asOf: asOf)
        if profile.method.usesAcademicCore {
            return academicCoreResult(profile: profile, report: report)
        }
        let isUC = profile.method == .ucFullyWeighted || profile.method == .ucUnweighted
        var result = CollegeGPAResult(profile: profile, records: [], skipped: report.skippedRecords)
        for source in report.includedRecords {
            let classification = CollegeCourseClassification(source.courseName)
            if isUC, classification.isKnownNonAcademic {
                result.omittedRecords.append(source)
                continue
            }
            var record = source
            if profile.method == .ucFullyWeighted, record.percentage >= 70, classification.isAPOrIB {
                record.points += 1
            }
            result.records.append(record)
        }
        if isUC {
            result.calculationNotes.append("UC A–G eligibility is unverified for the remaining courses, including arts and electives. Course names and recognized district aliases identify levels approximately; credits and summer placement are unavailable.")
            if !result.omittedRecords.isEmpty {
                let count = result.omittedRecords.count
                result.calculationNotes.append("\(count) completed semester record\(count == 1 ? " is" : "s are") recognized as PE, athletics, health or nonacademic support and omitted from the UC estimate.")
            }
        }
        return result
    }
    /// Local advanced-course exceptions and Honors labels do not establish UC
    /// out-of-state eligibility. Explicit AP/IB names are still an estimate.
    static func isExplicitAPOrIB(_ name: String) -> Bool {
        let level = CollegeCourseClassification(name)
        return level.isAPOrIB
    }

    private static func academicCoreResult(profile: CollegeProfile, report: GPAConversionReport) -> CollegeGPAResult {
        var result = CollegeGPAResult(profile: profile, records: [], skipped: report.skippedRecords)
        var unknownCount = 0
        var hasUnverifiedArtHistory = false
        var uncertainBonusCount = 0
        for source in report.includedRecords {
            let classification = CollegeCourseClassification(source.courseName)
            let eligibility = classification.eligibility(for: profile.method)
            guard eligibility == .included else {
                result.omittedRecords.append(source)
                if eligibility == .unknown {
                    unknownCount += 1
                    hasUnverifiedArtHistory = hasUnverifiedArtHistory || classification.isArtHistory
                }
                continue
            }
            var record = source
            let bonus = classification.bonus(for: profile.method)
            if bonus > 0, record.percentage < 70 {
                if profile.method != .fsuWeighted { uncertainBonusCount += 1 }
            } else {
                record.points += bonus
            }
            result.records.append(record)
        }
        let excludedCount = result.omittedRecords.count - unknownCount
        result.calculationNotes.append("Course names identify subjects and levels approximately. Each completed semester counts equally; credits and official course classifications are unavailable.")
        if excludedCount > 0 {
            result.calculationNotes.append("\(excludedCount) completed semester record\(excludedCount == 1 ? " is" : "s are") outside this method's recognized subjects and omitted.")
        }
        if unknownCount > 0 {
            result.calculationNotes.append("College subject eligibility for \(unknownCount) completed semester record\(unknownCount == 1 ? " is" : "s is") unverified. Elevate cannot calculate this estimate until course eligibility is known.")
            if hasUnverifiedArtHistory {
                result.calculationNotes.append("Elevate has not verified whether this college counts Art History as academic core. The estimate is unavailable; its grades have not been silently included or excluded from an average.")
            }
            result.unavailableReason = "Course eligibility is unverified."
        }
        if uncertainBonusCount > 0 {
            result.calculationNotes.append("Elevate has not verified bonus treatment for \(uncertainBonusCount) eligible semester grade\(uncertainBonusCount == 1 ? "" : "s") below C. The estimate is unavailable; these grades have not been dropped from the average.")
            result.unavailableReason = "Bonus treatment for lower grades is unverified."
        }
        return result
    }
}

/// Course titles are evidence for a labelled estimate, not official subject codes.
/// Keep college recognition independent of the district's advanced-course bonuses.
private struct CollegeCourseClassification {
    enum Eligibility { case included, excluded, unknown }
    let tokens: [String]
    let name: String
    let isPreLevel: Bool
    let isAP: Bool
    let isAPOrIB: Bool
    let isAICE: Bool
    let isDualEnrollment: Bool
    let isHonors: Bool
    let catalogKey: String
    let subjectName: String

    init(_ title: String) {
        tokens = title.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        name = tokens.joined(separator: " ")
        catalogKey = TranscriptCreditCalculator.equivalenceKey(for: title)
        subjectName = Self.catalogSubjects[catalogKey] ?? name
        // A compact AP code is evidence only when the complete title
        // resolves to an existing exact district alias, never a substring guess.
        let matchedAlias = catalogKey != TranscriptCreditCalculator.normalize(title)
        let apCodes: Set<String> = ["APENG3", "APENGLAN", "APENG4", "APENGLIT", "APSTATS", "APCALCAB", "APCALCBC",
            "APBIO2", "APCHEM2", "APPHYS1", "APPHYS2", "APPHYSC", "APENVIR", "APHUMGEO", "APWHIST",
            "APUSH", "APUSHIST", "APUSGOVT", "APMACECO", "APMICECO", "APHISART", "APCSP", "APTACSA"]
        let codedAP = matchedAlias && tokens.first.map(apCodes.contains) == true
        isPreLevel = tokens.contains(where: { ["PREAP", "PREIB", "PREAICE"].contains($0) })
            || name.contains("PRE AP") || name.contains("PRE IB") || name.contains("PRE AICE")
        isAP = !isPreLevel && (tokens.first == "AP" || tokens.last == "AP" || codedAP
            || APCapstoneCourse.matching(title) != nil || name.hasPrefix("ADVANCED PLACEMENT "))
        isAPOrIB = isAP || (!isPreLevel && (tokens.first == "IB" || tokens.last == "IB"
            || name.hasPrefix("INTERNATIONAL BACCALAUREATE ")))
        isAICE = !isPreLevel && (tokens.first == "AICE" || tokens.last == "AICE")
        isDualEnrollment = name.contains("DUAL ENROLLMENT") || name.contains("DUAL CREDIT")
            || tokens.first == "DE" || tokens.last == "DE" || tokens.first == "DC" || tokens.last == "DC"
        isHonors = tokens.contains(where: { ["HONORS", "HONOR", "HON"].contains($0) }) || tokens.last == "H"
    }

    /// Reuse the catalog's exact alias resolution, but apply college subject
    /// policy here. Texas science/elective credit never establishes college core.
    private static let catalogSubjects: [String: String] = [
        "english1": "ENGLISH", "english2": "ENGLISH", "english3": "ENGLISH", "english4": "ENGLISH",
        "algebra1": "ALGEBRA", "algebra2": "ALGEBRA", "geometry": "GEOMETRY", "mathmodels": "MATH",
        "precalculus": "PRECALCULUS", "statistics": "STATISTICS", "apstatistics": "STATISTICS",
        "statistics2": "STATISTICS", "calculus": "CALCULUS", "calculusab": "CALCULUS", "calculusbc": "CALCULUS",
        "multivariable": "CALCULUS", "linearalgebra": "ALGEBRA",
        "biology": "BIOLOGY", "biology2": "BIOLOGY", "chemistry": "CHEMISTRY", "chemistry2": "CHEMISTRY",
        "physics": "PHYSICS", "physics1": "PHYSICS", "physics2": "PHYSICS", "physics12": "PHYSICS",
        "physicsc": "PHYSICS", "ipc": "PHYSICS CHEMISTRY", "environmentalsystems": "ENVIRONMENTAL SCIENCE",
        "environmentalscience": "ENVIRONMENTAL SCIENCE", "earthspace": "EARTH SCIENCE",
        "astronomy": "ASTRONOMY", "organicchemistry": "CHEMISTRY", "anatomy": "ANATOMY",
        "worldgeography": "GEOGRAPHY", "worldhistory": "HISTORY", "ushistory": "HISTORY",
        "government": "GOVERNMENT", "economics": "ECONOMICS", "macro": "MACROECONOMICS", "micro": "MICROECONOMICS",
        "arthistory": "ART HISTORY", "artmethods": "ART", "artmethods2": "ART", "musictheory": "MUSIC THEORY",
        "guitar": "GUITAR", "appliedmusic": "MUSIC", "health": "HEALTH", "healthscience": "HEALTH",
        "outdooreducation": "PHYSICAL EDUCATION", "peerpartners": "PEER PARTNERS", "maps": "MAPS",
        "officeaide": "OFFICE AIDE", "csp": "COMPUTER SCIENCE", "csa": "COMPUTER SCIENCE",
        "cs2": "COMPUTER SCIENCE", "cs3": "COMPUTER SCIENCE", "csind": "COMPUTER SCIENCE",
        "robotics1": "ROBOTICS", "robotics2": "ROBOTICS", "robotics3": "ROBOTICS",
        "engineering": "ENGINEERING", "appliedengineering": "ENGINEERING", "financialliteracy": "FINANCIAL LITERACY",
    ]

    /// These exclusions are narrower than academic core: arts and academic
    /// electives may satisfy UC A–G, so their district category cannot exclude them.
    var isKnownNonAcademic: Bool {
        let words = Set((name + " " + subjectName).split(separator: " ").map(String.init))
        let excluded: Set<String> = ["ATHLETICS", "PE", "FOOTBALL", "BASKETBALL", "VOLLEYBALL",
            "TENNIS", "WRESTLING", "AEROBICS", "SOCCER", "BASEBALL", "SOFTBALL", "TRACK", "GOLF",
            "SWIMMING", "CHEERLEADING", "YOGA", "MAPS"]
        let phrases = ["PHYSICAL EDUCATION", "PERSONAL FITNESS", "TEAM SPORTS", "CROSS COUNTRY",
            "SKILL BASED LIFETIME ACTIVITIES", "LIFETIME FITNESS", "LIFETIME RECREATION",
            "OUTDOOR EDUCATION", "OFFICE AIDE", "TEACHER AIDE", "PEER PARTNERS", "EXCUSED PERIOD"]
        // Health education is excluded; a health-science elective could be
        // A–G approved and must retain the general eligibility caveat.
        return catalogKey == "health" || !excluded.isDisjoint(with: words)
            || phrases.contains { name.contains($0) || subjectName.contains($0) }
    }

    func bonus(for method: CollegeGPAMethod) -> Double {
        if method == .ugaWeighted { return isAPOrIB ? 1 : 0 }
        if isAPOrIB || isAICE || isDualEnrollment { return 1 }
        return isHonors || isPreLevel ? 0.5 : 0
    }

    var isArtHistory: Bool { catalogKey == "arthistory" || name.contains("ART HISTORY") }

    func eligibility(for method: CollegeGPAMethod) -> Eligibility {
        let subjectTokens = Set(subjectName.split(separator: " ").map(String.init))
        if method == .ufWeighted, isAPOrIB || isAICE { return .included }
        // UGA explicitly lists Art History as social science. UF's AP/IB/AICE
        // elective rule above is also explicit. A school fine-arts label alone
        // cannot resolve the other colleges' admissions classification.
        if isArtHistory { return method == .ugaWeighted ? .included : .unknown }
        if method == .ugaWeighted, isAP,
           subjectTokens.contains("ART") || subjectName.contains("MUSIC THEORY") { return .included }
        if isKnownNonAcademic { return .excluded }

        // Exclusions precede broad subject words: Business Math is not Math;
        // Computer Science is not an inferred natural-science course.
        let excludedPhrases = ["COMPUTER SCIENCE", "FOOD SCIENCE", "AGRICULTURAL SCIENCE", "BUSINESS MATH",
            "FINANCIAL LITERACY", "REMEDIAL MATH", "BUSINESS LAW", "CRIMINAL JUSTICE", "HOME ECONOMICS",
            "CONSUMER ECONOMICS", "PHYSICAL EDUCATION"]
        let excludedWords: Set<String> = ["DEBATE", "JOURNALISM", "YEARBOOK", "SPEECH", "READING", "ACCOUNTING",
            "HEALTH", "ETHICS", "ATHLETICS", "PE", "BAND", "ORCHESTRA", "CHOIR", "DANCE", "THEATRE", "THEATER",
            "ROBOTICS", "ENGINEERING", "CYBERSECURITY", "GUITAR"]
        if excludedPhrases.contains(where: { name.contains($0) || subjectName.contains($0) })
            || !excludedWords.isDisjoint(with: tokens) || !excludedWords.isDisjoint(with: subjectTokens) { return .excluded }

        let coreWords: Set<String> = ["ENGLISH", "LITERATURE", "COMPOSITION", "WRITING", "ALGEBRA", "GEOMETRY",
            "CALCULUS", "PRECALCULUS", "STATISTICS", "STATS", "TRIGONOMETRY", "MATH", "MATHEMATICS",
            "BIOLOGY", "BIOCHEMISTRY", "CHEMISTRY", "PHYSICS", "ANATOMY", "ASTRONOMY", "BOTANY", "ECOLOGY",
            "ENTOMOLOGY", "GEOLOGY", "GENETICS", "MICROBIOLOGY", "OCEANOGRAPHY", "ZOOLOGY", "SCIENCE",
            "HISTORY", "GOVERNMENT", "CIVICS", "ECONOMICS", "MACROECONOMICS", "MICROECONOMICS", "PSYCHOLOGY", "SOCIOLOGY", "GEOGRAPHY",
            "ANTHROPOLOGY", "PHILOSOPHY", "SPANISH", "FRENCH", "GERMAN", "LATIN", "MANDARIN", "CHINESE",
            "JAPANESE", "ITALIAN", "RUSSIAN", "ARABIC", "HEBREW", "KOREAN", "ASL"]
        if !coreWords.isDisjoint(with: subjectTokens) || !coreWords.isDisjoint(with: tokens) || name.contains("DIFFERENTIAL EQUATIONS")
            || name.contains("SIGN LANGUAGE") || name.contains("SOCIAL STUDIES") { return .included }
        if subjectTokens.contains("ART") || subjectTokens.contains("MUSIC") { return .excluded }
        return .unknown
    }
}
