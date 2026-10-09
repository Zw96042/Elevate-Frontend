import Foundation
import Testing
@testable import ElevateCore

@Suite("Automatic transcript credit estimates")
struct TranscriptCreditTests {
    @Test("Art history is fine arts; catalog special credits retain their full semester allocation")
    func catalogAllocations() {
        let report = calculate([
            row("AP Art History"), row("AP Physics 1&2"), row("AP Physics C"),
            row("Health", terms: "1-2", spring: nil),
            row("Multivariable Calculus", terms: "1-2", spring: nil),
            row("Linear Algebra", terms: "3-4", fall: nil),
        ])
        #expect(report.credits(for: .fineArts) == 1)
        #expect(report.credits(for: .science) == 4)
        #expect(report.credits(for: .health) == 0.5)
        #expect(report.credits(for: .math) == 1.5)
        #expect(report.unresolved.isEmpty)
    }

    @Test("Catalog aliases preserve advanced second science courses and Pre Calculus")
    func distinctCourses() {
        let report = calculate([
            row("Biology I"), row("AP Biology"), row("Chemistry I"), row("AP Chemistry"),
            row("Pre Calculus"), row("Calculus"), row("Statistics"), row("AP Statistics"),
            row("Statistics 2 Beyond Statistics"), row("Robotics II"), row("Robotics III"),
            row("Computer Science III"), row("AP Cybersecurity"), row("AP English 2"),
        ])
        #expect(report.credits(for: .science) == 5)
        #expect(report.credits(for: .math) == 5)
        #expect(report.credits(for: .elective) == 3)
        #expect(report.credits(for: .english) == 1)
        #expect(report.unresolved.isEmpty)
        #expect(TranscriptCreditCalculator.normalize("Pre Calculus") != TranscriptCreditCalculator.normalize("Calculus"))
    }

    @Test("Middle-school credit includes eligible courses only, with language 7/8 and legacy IPC rules")
    func middleSchool() {
        let report = calculate([
            row("Algebra I", grade: 8), row("Geometry", grade: 8), row("Health", grade: 8, terms: "1-2", spring: nil),
            row("Spanish 7", grade: 7), row("Spanish 8", grade: 8), row("Spanish I", grade: 8),
            row("Biology", grade: 8), row("World History", grade: 8),
            row("IPC", year: "2020-2021", grade: 8), row("IPC", year: "2024-2025", grade: 8),
        ])
        #expect(report.credits(for: .math) == 2)
        #expect(report.credits(for: .health) == 0.5)
        #expect(report.credits(for: .worldLanguage) == 1)
        #expect(report.credits(for: .science) == 0)
        #expect(report.credits(for: .socialStudies) == 0)
        #expect(report.credits(for: .elective) == 1)
        #expect(report.records.filter { $0.name == "IPC" && $0.academicYear == "2024-2025" }.allSatisfy { $0.status == .excluded })
    }

    @Test("Disjoint semester rows, duplicate source rows and repeated equivalent courses count once")
    func repeatedRows() {
        let fall = row("English I", terms: "1-2", spring: nil)
        let spring = row("English I Honors", terms: "3-4", fall: nil)
        let report = calculate([fall, fall, spring, row("English I", year: "2024-2025")])
        #expect(report.total == 1)
        #expect(report.records.count == 4)
        let retry = calculate([
            row("English II", year: "2023-2024", fall: "55", spring: "80"),
            row("English II Honors", year: "2024-2025", fall: "80", spring: "80"),
        ])
        #expect(retry.total == 1)
    }

    @Test("Accelerated middle-school estimates retain the documented grade eligibility")
    func middleSchoolGradeEligibility() {
        let report = calculate([
            row("Geometry", grade: 6), row("Algebra II", grade: 7), row("Spanish I", grade: 7),
            row("Health", grade: 7, terms: "1-2", spring: nil),
        ])
        #expect(report.total == 0)
        #expect(report.records.allSatisfy { $0.status == .excluded })
        #expect(calculate([row("Algebra I", grade: 6)]).total == 1)
    }

    @Test("Ordinary middle-school schedules do not become credit-review tasks")
    func ordinaryMiddleSchoolSchedule() {
        let names = ["English 8", "Language Arts 7", "Math 8 Accelerated", "Math 7/8 Compacted", "Science 8",
                     "Texas History", "US History", "Band", "Art 1", "PE", "Football", "Uncatalogued Exploratory"]
        let report = calculate(names.map { row($0, grade: 8) })
        #expect(report.total == 0)
        #expect(report.unresolved.isEmpty)
        #expect(report.records.allSatisfy { $0.status == .excluded })
        #expect(calculate([row("Math 8 Accelerated", year: "unknown", grade: 8)]).unresolved.isEmpty)
        // Unknown high-school course identities still need a real allocation.
        #expect(calculate([row("Uncatalogued Seminar", grade: 10)]).unresolved.count == 2)
    }

    @Test("Middle-school high-school aliases retain eligibility and source-bound corrections")
    func acceleratedAliasesAndCorrections() throws {
        let report = calculate([
            row("PreAP ALG I", grade: 6), row("ALG1H", grade: 8), row("GEO H", grade: 7), row("GEOMP", grade: 8), row("ALG II Honors", grade: 8),
            row("SPN1", grade: 8), row("SPN1H", grade: 8), row("Spanish Level I", grade: 8),
            row("HLTH ED", grade: 8, terms: "1-2", spring: nil),
        ])
        #expect(report.credits(for: .math) == 3)
        #expect(report.credits(for: .worldLanguage) == 1)
        #expect(report.credits(for: .health) == 0.5)
        #expect(report.unresolved.isEmpty)
        let rows = [row("PE", grade: 8, terms: "1-2", spring: nil)]
        let excluded = try #require(calculate(rows).records.first)
        let correction = TranscriptCreditOverride(id: excluded.id, credits: 0.5, subject: .physicalEducation)
        let corrected = TranscriptCreditCalculator.calculate(courses: [], planningTranscriptCourses: rows,
            overrides: [correction], asOf: date)
        #expect(corrected.total == 0.5)
        #expect(corrected.records.first?.id == excluded.id)
        #expect(corrected.records.first?.status == .corrected)
        #expect(corrected.orphanedOverrideIDs.isEmpty)
    }

    @Test("Actual athletics recognize roster variants without classifying sport-related academic titles")
    func athleticsAliases() {
        for name in ["Water Polo", "Waterpolo 1", "Boys & Girls Water Polo", "Water Polo JV", "Football 9th Grade",
                     "Football 9th Grade - AT832A/B", "Girls Volleyball 1", "Tennis Junior Varsity", "Swimming/Diving", "Cheerleader", "9th Grade Girls Athletics",
                     "Basketball Boys 9th Grade AT833A/B*", "Volleyball Girls 9th Grade - AT830A/B*", "Girls Track & Field Varsity",
                     "Swimming and Diving Junior Varsity", "AT031C", "PE880D"] {
            let report = calculate([row(name)])
            #expect(report.credits(for: .physicalEducation) == 1)
            #expect(report.unresolved.isEmpty)
        }
        for name in ["Football History", "Water Polo Management", "Sports Science"] {
            #expect(calculate([row(name)]).total == 0)
            #expect(calculate([row(name)]).unresolved.count == 2)
        }
        let duplicates = calculate([row("Water Polo"), row("Boys Waterpolo 1"), row("Water Polo", year: "2024-2025")])
        #expect(duplicates.credits(for: .physicalEducation) == 2)
        #expect(calculate([row("Water Polo", grade: 8)]).unresolved.isEmpty)
        #expect(calculate([row("Water Polo", grade: 8)]).total == 0)
        #expect(calculate([row("PE"), row("Physical Education"), row("P.E.")]).total == 1)
    }

    @Test("Catalog display suffixes and sports medicine distinguish subject and equivalent credit")
    func catalogNamesAndSportsMedicine() {
        let report = calculate([
            row("AP LANGUAGE AND COMPOSITION (AP ENGLISH III) - LA118 (APENGLAN)"),
            row("ALGEBRA II HONORS - MA240 (ALG2)"), row("AP COMPUTER SCIENCE PRINCIPLES - TC736 (PRINIT)"),
            row("ATHLETIC TRAINING - SPORTS MEDICINE (SPORTMD1, SPORTMD2, SPORTMD3)"),
            row("AT100A/B"), row("SPORTMD1"),
        ])
        #expect(report.credits(for: .english) == 1)
        #expect(report.credits(for: .math) == 1)
        #expect(report.credits(for: .elective) == 2)
        #expect(report.credits(for: .physicalEducation) == 0)
        #expect(report.unresolved.isEmpty)
        #expect(calculate([row("Football History - LA999")]).unresolved.count == 2)
        #expect(calculate([row("Sports Management - TC999")]).credits(for: .physicalEducation) == 0)
    }

    @Test("Current athletics aliases share enrollment allocation and completed-credit limits")
    func currentAthleticsAliases() {
        let report = current([live("Water Polo"), live("Boys Waterpolo 1")])
        #expect(report.count == 1)
        #expect(report.first?.credits == 1)
        #expect(report.first?.subject == .physicalEducation)
        let earned = TranscriptCreditCalculator.calculate(courses: [],
            planningTranscriptCourses: [row("Water Polo", year: "2026-2027", terms: "1-2", spring: nil)],
            overrides: [], asOf: ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z")!)
        let afterFall = TranscriptCreditCalculator.currentCourses(courses: [live("Boys Water Polo")], earned: earned,
            asOf: ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z")!)
        #expect(earned.total == 0.5)
        #expect(afterFall.first?.credits == 0.5)
        var middle = live("English 8")
        middle.gradeYear = 8
        #expect(current([middle]).first?.status == .excluded)
        #expect(current([middle]).first?.credits == 0)
    }

    @Test("Conflicting equivalent grades remain reviewable without awarding that semester")
    func conflictingRows() {
        let report = calculate([row("English I", fall: "80"), row("English I Honors", fall: "90")])
        #expect(report.total == 0.5)
        #expect(report.unresolved.count == 1)
        let conflict = calculate([row("English I", fall: "80", spring: nil), row("English I", fall: "P", spring: nil)])
        #expect(conflict.total == 0)
    }

    @Test("Fall averaging needs provenance review; spring failure is never averaged up")
    func averagingBoundary() {
        let fallReview = calculate([row("English I", fall: "65", spring: "85")])
        #expect(fallReview.total == 0.5)
        #expect(fallReview.unresolved.first?.semester == .sm1)
        let springFail = calculate([row("English I", fall: "95", spring: "65")])
        #expect(springFail.total == 0.5)
        #expect(springFail.records.first { $0.semester == .sm2 }?.status == .notEarned)
        let unrecoverable = calculate([row("English I", fall: "64", spring: "95")])
        #expect(unrecoverable.unresolved.isEmpty)
    }

