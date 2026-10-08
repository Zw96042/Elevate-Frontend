import Foundation
import Testing
@testable import ElevateCore

@Suite("Official grade change journal")
struct GradeJournalTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func assignment(_ name: String = "Quiz", score: Double? = 90,
                            earned: Double? = 9, possible: Double? = 10,
                            statuses: [String] = [], note: String = "") -> GradeInfoAssignment {
        GradeInfoAssignment(date: "10/04/2026", name: name, grade: nil, score: score,
                            pointsEarned: earned, pointsTotal: possible,
                            meta: statuses.map { AssignmentMeta(type: $0, note: note) })
    }
    private func gradebook(_ assignments: [GradeInfoAssignment]) -> GradeInfoResult {
        GradeInfoResult(course: "Synthetic course", instructor: "Synthetic teacher", period: 1,
                        litName: "Quarter 1", litBegin: nil, litEnd: nil,
                        gradebook: [GradeCategory(category: "Daily", weight: 100, adjustedWeight: nil, assignments: assignments)],
                        score: 90, grade: 90)
    }
    private func course(score: Double) -> UnifiedCourseData {
        UnifiedCourseData(courseId: 1, corNumId: "synthetic-course", stuId: "synthetic-student", section: "01",
                          gbId: "synthetic-book", courseName: "Synthetic", instructor: nil, period: 1, time: nil,
                          semester: .fall, termLength: "1-2", gradeYear: 12,
                          currentScores: [BucketScore(bucket: "Q1", score: score)], historicalGrades: HistoricalGrades())
    }
    @discardableResult
    private func observe(_ journal: inout GradeJournal, _ assignments: [GradeInfoAssignment],
                         seconds: TimeInterval, source: GradeObservationSource = .freshValidated) -> [GradeJournalEvent] {
        journal.observeAssignments(gradebook(assignments), courseID: "course", courseName: "Synthetic course",
                                   term: .q1, source: source, at: t0.addingTimeInterval(seconds))
    }

    @Test func initialScopesSeedSilentlyAndUnavailableIsDistinctFromZero() throws {
        var journal = GradeJournal()
        #expect(journal.observeAverage(nil, courseID: "course", courseName: "Synthetic", term: .q1, at: t0).isEmpty)
        let available = try #require(journal.observeAverage(0, courseID: "course", courseName: "Synthetic", term: .q1,
                                                          at: t0.addingTimeInterval(1)).first)
        #expect(available.previousScore == nil && available.currentScore == 0)
        #expect(available.kind == .averageChanged)
        let unavailable = try #require(journal.observeAverage(nil, courseID: "course", courseName: "Synthetic", term: .q1,
                                                            at: t0.addingTimeInterval(2)).first)
        #expect(unavailable.previousScore == 0 && unavailable.currentScore == nil)
        #expect(journal.observeAverage(20, courseID: "course", courseName: "Synthetic", term: .q2, at: t0).isEmpty)
        #expect(journal.observeAverage(20, courseID: "another-year", courseName: "Synthetic", term: .q1, at: t0).isEmpty)
        #expect(observe(&journal, [assignment()], seconds: 3).isEmpty)
    }

    @Test func assignmentsRecordNewScorePointsAndStatusesWithoutNoteNoise() throws {
        var journal = GradeJournal()
        #expect(observe(&journal, [assignment(score: nil, earned: nil, statuses: ["missing"])], seconds: 0).isEmpty)
        let posted = try #require(observe(&journal, [assignment(score: 0, earned: 0)], seconds: 1).first)
        #expect(posted.kind == .assignmentChanged)
        #expect(posted.previousAssignment?.score == nil && posted.currentAssignment?.score == 0)
        #expect(posted.previousAssignment?.statuses == ["missing"] && posted.currentAssignment?.statuses == [])
        let status = try #require(observe(&journal, [assignment(score: 0, earned: 0, statuses: ["noCount"])], seconds: 2).first)
        #expect(status.currentAssignment?.statuses == ["nocount"])
        #expect(observe(&journal, [assignment(score: 0, earned: 0, statuses: ["noCount"], note: "Different explanation")], seconds: 3).isEmpty)
        let points = try #require(observe(&journal, [assignment(score: 0, earned: 0, possible: 20, statuses: ["noCount"])], seconds: 4).first)
        #expect(points.currentAssignment?.pointsPossible == 20)
        let new = try #require(observe(&journal, [assignment(score: 0, earned: 0, possible: 20, statuses: ["noCount"]), assignment("New work")], seconds: 5).first)
        #expect(new.kind == .assignmentAdded && new.assignmentName == "New work")
        #expect(new.observedAt == t0.addingTimeInterval(5))
    }

    @Test func rejectedObservationsNeverAdvanceBaselines() {
        var journal = GradeJournal()
        observe(&journal, [assignment()], seconds: 10)
        for source: GradeObservationSource in [.cached, .failed, .staleAccount, .cancelled, .incomplete] {
            #expect(observe(&journal, [assignment(score: 10)], seconds: 20, source: source).isEmpty)
        }
        #expect(observe(&journal, [assignment(score: 10)], seconds: 9).isEmpty)
        #expect(observe(&journal, [assignment(score: 10)], seconds: 10).isEmpty)
        #expect(observe(&journal, [assignment(score: .nan)], seconds: 20).isEmpty)
        #expect(observe(&journal, [assignment(earned: .infinity)], seconds: 20).isEmpty)
        #expect(observe(&journal, [assignment(score: 91)], seconds: 11).first?.previousScore == 90)
        #expect(observe(&journal, [assignment(score: 91)], seconds: 12).isEmpty)
        journal.observeAverage(90, courseID: "course", courseName: "Synthetic", term: .q1, at: t0)
        #expect(journal.observeAverage(.nan, courseID: "course", courseName: "Synthetic", term: .q1,
                                       at: t0.addingTimeInterval(1)).isEmpty)
        #expect(journal.observeAverage(91, courseID: "course", courseName: "Synthetic", term: .q1,
                                       at: t0.addingTimeInterval(2)).first?.previousScore == 90)
    }

    @Test func missingRowsDoNotInventRemovalAndDuplicatesReseedSilently() {
        var journal = GradeJournal()
        observe(&journal, [assignment(), assignment("Essay")], seconds: 0)
        #expect(observe(&journal, [], seconds: 1).isEmpty)
        #expect(observe(&journal, [assignment(), assignment("Essay")], seconds: 2).isEmpty)
        #expect(observe(&journal, [assignment(), assignment(score: 10)], seconds: 3).isEmpty)
        #expect(observe(&journal, [], seconds: 4).isEmpty)
        #expect(observe(&journal, [assignment(score: 50)], seconds: 5).isEmpty)
        #expect(observe(&journal, [assignment(score: 60)], seconds: 6).first?.previousScore == 50)
    }

