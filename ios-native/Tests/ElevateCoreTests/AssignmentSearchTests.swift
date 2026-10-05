import Foundation
import Testing
@testable import ElevateCore

struct AssignmentSearchTests {
    @Test("All query tokens may match across title, class, and category")
    func multipleFields() {
        let assignments = [
            assignment(id: "essay", title: "Persuasive essay", courseName: "English III", category: "Major grades"),
            assignment(id: "quiz", title: "Persuasive techniques quiz", courseName: "English III", category: "Daily work"),
            assignment(id: "lab", title: "Lab report", courseName: "Chemistry", category: "Major grades"),
        ]
        #expect(AssignmentSearch.results(in: assignments, query: "essay english major").map(\.id) == ["essay"])
        #expect(AssignmentSearch.results(in: assignments, query: "major chemistry").map(\.id) == ["lab"])
        #expect(AssignmentSearch.results(in: assignments, query: "english daily persuasive").map(\.id) == ["quiz"])
        #expect(AssignmentSearch.results(in: assignments, query: "essay chemistry").isEmpty)
    }

    @Test("Matching ignores case, accents, underscores, and repeated whitespace")
    func normalizedText() {
        let assignments = [assignment(id: "fixture", title: "Résumé_Éssay",
                                      courseName: "AP_FRENCH", category: "Écriture\n  majeure")]
        for query in ["resume essay french", "RÉSUMÉ_ESSAY\tAP", "  ecriture\n\nMAJEURE  "] {
            #expect(AssignmentSearch.results(in: assignments, query: query).map(\.id) == ["fixture"])
        }
        #expect(AssignmentSearch.results(in: assignments, query: "Re\u{301}sume\u{301}").count == 1)
    }

    @Test("Empty and unmatched queries produce no results")
    func noResults() {
        let assignments = [assignment(id: "quiz", title: "Quiz 1")]
        for query in ["", " \n\t ", "___", "nonexistent"] {
            #expect(AssignmentSearch.results(in: assignments, query: query).isEmpty)
        }
        #expect(AssignmentSearch.results(in: [], query: "quiz").isEmpty)
    }

    @Test("Results sort by normalized school day and put undated work last")
    func dateOrdering() {
        let assignments = [
            assignment(id: "undated", title: "Quiz A", sourceDate: "unreadable"),
            assignment(id: "later", title: "Quiz B", sourceDate: "10/12/26"),
            assignment(id: "earlier", title: "Quiz Z", sourceDate: "10/2/2026"),
            assignment(id: "iso", title: "Quiz C", sourceDate: "2026-10-04"),
        ]
        let result = AssignmentSearch.results(in: assignments, query: "quiz")
        #expect(result.map(\.id) == ["earlier", "iso", "later", "undated"])
        #expect(result.map(\.sourceDate) == ["10/2/2026", "2026-10-04", "10/12/26", "unreadable"])
        #expect(result.last?.date == nil)
    }

    @Test("Tie ordering uses folded title, class, and ID while preserving distinct assignments")
    func deterministicTiesAndDistinctIDs() {
        let assignments = [
            assignment(id: "c", title: "Quiz beta", courseName: "English"),
            assignment(id: "b", title: "QUIZ_ÁLPHA", courseName: "Biology"),
            assignment(id: "a", title: "Quiz alpha", courseName: "Biology"),
            assignment(id: "d", title: "Quiz alpha", courseName: "Chemistry"),
        ]
        let result = AssignmentSearch.results(in: assignments, query: "quiz")
        #expect(result.map(\.id) == ["a", "b", "d", "c"])
        #expect(result.count == assignments.count)
        #expect(AssignmentSearch.results(in: assignments.reversed(), query: "quiz") == result)
        #expect(result.first?.course.courseName == "Biology")
    }

    @Test("Query tokenization is bounded to 256 characters")
    func boundedQuery() {
        let assignments = [assignment(id: "essay", title: "Essay")]
        let first256 = "essay" + String(repeating: " ", count: 251)
        #expect(first256.count == 256)
        let longQuery = first256 + String(repeating: "unmatched ", count: 10_000)
        #expect(AssignmentSearch.results(in: assignments, query: longQuery).map(\.id) == ["essay"])
        #expect(AssignmentSearch.results(in: assignments, query: String(repeating: " ", count: 10_000) + "essay").isEmpty)
    }

    private func assignment(id: String, title: String, courseName: String = "English",
                            category: String = "Daily work", sourceDate: String = "2026-10-04") -> CalendarAssignment {
        let course = UnifiedCourseData(
            courseId: 1, corNumId: "1", stuId: "synthetic", section: "1", gbId: "1",
            courseName: courseName, instructor: nil, period: nil, time: nil, semester: .fall,
            termLength: "1 - 2", gradeYear: 11, currentScores: [],
            historicalGrades: HistoricalGrades(pr1: nil, pr2: nil, pr3: nil, pr4: nil,
                pr5: nil, pr6: nil, pr7: nil, pr8: nil, rc1: nil, rc2: nil, rc3: nil, rc4: nil,
                ex1: nil, ex2: nil, sm1: nil, sm2: nil, finalGrade: nil)
        )
        return CalendarAssignment(id: id, course: course, term: .q1,
                                  date: SchoolCalendarDate.normalize(sourceDate), sourceDate: sourceDate,
                                  title: title, category: category, meta: [])
    }
}
