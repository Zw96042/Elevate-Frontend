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

