import Foundation
import WidgetKit

#if DEBUG
enum SampleData {
    private static let studentID = "sample-student"

    static let courses: [UnifiedCourseData] = {
        let seniorCourses: [(String, String, Double)] = [
            ("LINEAR ALGEBRA", "Isaac Grombacher-Brown", 96),
            ("MULTIVARIABLE CALCULUS", "Isaac Grombacher-Brown", 93),
            ("AP PHYSICS 1&2", "Andria Chaney", 89),
            ("STATISTICS 2 BEYOND STATISTICS", "Karen Chong", 97),
            ("AP ENGLISH 3", "Kathleen Murphy", 94),
            ("COMPUTER SCIENCE III", "Lynden Rosier", 100),
            ("AP CYBERSECURITY", "Darcie Gilde", 91),
            ("ROBOTICS II", "Norman Morgan", 98),
        ]
        let priorYears: [[(String, String, Double)]] = [
            [("ENGLISH 1 H", "Maya Chen", 92), ("GEOMETRY H", "Avery Hall", 95),
             ("BIOLOGY H", "Nina Patel", 90), ("WORLD GEOGRAPHY", "Owen Price", 94)],
            [("ENGLISH 2 H", "Maya Chen", 94), ("ALGEBRA II H", "Avery Hall", 96),
             ("CHEMISTRY H", "Nina Patel", 91), ("AP WORLD HISTORY", "Owen Price", 93)],
            [("AP ENGLISH 2", "Kathleen Murphy", 95), ("PRECALCULUS H", "Avery Hall", 97),
             ("AP PHYSICS", "Andria Chaney", 92), ("AP US HISTORY", "Owen Price", 96)],
        ]

        var result = seniorCourses.enumerated().map { index, item in
            course(name: item.0, instructor: item.1, score: item.2, gradeYear: 12, index: index)
        }
        for (offset, yearCourses) in priorYears.enumerated() {
            let year = offset + 9
            result += yearCourses.enumerated().map { index, item in
                course(name: item.0, instructor: item.1, score: item.2,
                       gradeYear: year, index: year * 10 + index)
            }
        }
        return result
    }()

    static let messages: [SkywardMessage] = [
        SkywardMessage(className: "Linear Algebra",
                       content: "The review packet is now posted. Focus on eigenvalues and diagonalization before Friday.",
                       date: "8/7/26 1:42 PM", from: "Isaac Grombacher-Brown",
                       messageRowId: "sample-message-1", subject: "Review packet posted"),
        SkywardMessage(className: "Administrator",
                       content: "The updated bell schedule begins Monday. First period starts at 8:30 AM.",
                       date: "8/7/26 10:15 AM", from: "Eanes ISD",
                       messageRowId: "sample-message-2", subject: "Administrator Message"),
        SkywardMessage(className: "AP Physics 1&2",
                       content: "Your momentum lab has been returned with feedback. Please review the uncertainty section.",
                       date: "8/6/26 4:08 PM", from: "Andria Chaney",
                       messageRowId: "sample-message-3", subject: "Lab feedback available"),
        SkywardMessage(className: "AP English 3",
                       content: "Bring an annotated copy of the essay to class tomorrow.",
                       date: "8/6/26 12:31 PM", from: "Kathleen Murphy",
                       messageRowId: "sample-message-4", subject: "Seminar preparation"),
        SkywardMessage(className: "Robotics II",
                       content: "Team assignments and the first build brief are attached.",
                       date: "8/5/26 3:54 PM", from: "Norman Morgan",
                       messageRowId: "sample-message-5", subject: "Build teams announced"),
    ]

    static let widgetSnapshot = WidgetSnapshot(
        generatedAt: Date(),
        termShortName: "Q1",
        weightedGPA: 103.5,
        unweightedGPA: 94.75,
        courses: courses.filter { $0.gradeYear == 12 }.map {
            WidgetSnapshot.CourseGrade(
                name: ClassNameFormatter.format($0.courseName.replacingOccurrences(of: " ", with: "_")),
                score: $0.currentScores.first { $0.bucket == "Q1" }?.score
            )
        },
        recentGrades: [
            .init(className: "Linear Algebra", name: "Matrix Transformations", gradeText: "96", date: "8/7/26"),
            .init(className: "AP English 3", name: "Rhetorical Analysis", gradeText: "94", date: "8/6/26"),
            .init(className: "Robotics II", name: "Drive Train Check", gradeText: "49/50", date: "8/5/26"),
            .init(className: "AP Cybersecurity", name: "Threat Model", gradeText: "91", date: "8/4/26"),
        ],
        missingAssignments: [
            .init(className: "AP Physics 1&2", name: "Momentum Corrections", gradeText: "", date: "8/6/26"),
            .init(className: "AP English 3", name: "Reading Notes", gradeText: "", date: "8/5/26"),
        ],
        absentAssignments: [
            .init(className: "Statistics 2", name: "Sampling Lab", gradeText: "", date: "8/4/26"),
        ],
        gpaHistory: [
            .init(term: "Q1 ’25", weighted: 100.8),
            .init(term: "Q2 ’25", weighted: 101.4),
            .init(term: "Q3 ’26", weighted: 102.1),
            .init(term: "Q4 ’26", weighted: 101.9),
            .init(term: "Q1 ’27", weighted: 103.5),
        ],
        messages: messages.map {
            .init(from: $0.from, subject: $0.subject, date: $0.date,
                  isAdministrator: $0.isAdministrator)
        }
    )

    static func gradeInfo(for params: GradeInfoParams) -> GradeInfoResult? {
        guard params.stuId == studentID,
              let course = courses.first(where: { $0.corNumId == params.corNumId }) else { return nil }
        let scoreBucket: String
        switch params.bucket {
        case "TERM 6": scoreBucket = "Q2"
        case "SEM 1": scoreBucket = "S1"
        case "TERM 9": scoreBucket = "Q3"
        case "TERM 12": scoreBucket = "Q4"
        case "SEM 2": scoreBucket = "S2"
        default: scoreBucket = "Q1"
        }
        let score = course.currentScores.first { $0.bucket == scoreBucket }?.score

        return GradeInfoResult(
            course: course.courseName,
            instructor: course.instructor ?? "",
            period: course.period,
            litName: params.bucket,
            litBegin: "8/1/26",
            litEnd: "10/25/26",
            gradebook: [
                GradeCategory(category: "Assignments", weight: 30, adjustedWeight: 30, assignments: [
                    assignment("Practice Set 1", earned: 19, total: 20, date: "8/7/26"),
                    assignment("Reading Notes", earned: nil, total: 10, date: "8/6/26",
                               meta: [.init(type: "missing", note: "Missing")]),
                    assignment("Warm-up Check", earned: 10, total: 10, date: "8/5/26",
                               meta: [.init(type: "noCount", note: "No count")]),
                ]),
                GradeCategory(category: "Assessments", weight: 50, adjustedWeight: 50, assignments: [
                    assignment("Unit 1 Assessment", earned: score, total: 100, date: "8/4/26"),
                    assignment("Concept Check", earned: 18, total: 20, date: "8/2/26"),
                ]),
                GradeCategory(category: "Labs", weight: 20, adjustedWeight: 20, assignments: [
                    assignment("Sampling Lab", earned: nil, total: 25, date: "8/3/26",
                               meta: [.init(type: "absent", note: "Absent")]),
                    assignment("Data Analysis", earned: 24, total: 25, date: "8/1/26"),
                ]),
            ],
            score: score,
            grade: score.map { Int($0.rounded()) }
        )
    }

    static func install() {
        WidgetSnapshotStore.save(widgetSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
        seedWhatIfData()
    }

    private static func seedWhatIfData() {
        let key = "sampleWhatIfDataV1"
        guard !UserDefaults.standard.bool(forKey: key), let course = courses.first else { return }
        let classKey = WhatIfStore.classKey(studentID: course.stuId, className: course.courseName, corNumId: course.corNumId,
                                            section: course.section, gbId: course.gbId)
        WhatIfStore.add(WhatIfAssignment(
            className: course.courseName, name: "Practice Quiz", term: "Q1",
            category: "Assessments", grade: 88, outOf: 100, dueDate: "8/7/26"
        ), classKey: classKey)
        WhatIfStore.add(WhatIfAssignment(
            className: course.courseName, name: "Optional Challenge", term: "Q1",
            category: "Assignments", grade: 10, outOf: 10, dueDate: "8/8/26", status: .noCount
        ), classKey: classKey)
        WhatIfStore.setShowCalculated(true, classKey: classKey)
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func course(name: String, instructor: String, score: Double,
                               gradeYear: Int, index: Int) -> UnifiedCourseData {
        let offset = Double((index % 4) - 1)
        return UnifiedCourseData(
            courseId: 10_000 + index,
            corNumId: "sample-\(gradeYear)-\(index)",
            stuId: studentID,
            section: "S\(index)",
            gbId: "GB\(index)",
            courseName: name,
            instructor: instructor,
            period: (index % 8) + 1,
            time: nil,
            semester: .both,
            termLength: "Full Year",
            gradeYear: gradeYear,
            currentScores: [
                .init(bucket: "Q1", score: score), .init(bucket: "Q2", score: score + offset),
                .init(bucket: "S1", score: score + 0.5), .init(bucket: "Q3", score: score - offset),
                .init(bucket: "Q4", score: score + 1), .init(bucket: "S2", score: score + 0.8),
            ],
            historicalGrades: history(score: score, offset: offset)
        )
    }

    private static func history(score: Double, offset: Double) -> HistoricalGrades {
        func value(_ delta: Double) -> String { String(format: "%.1f", score + delta) }
        return HistoricalGrades(
            pr1: value(-2.2), pr2: value(-1.4), pr3: value(-0.8), pr4: value(-0.2),
            pr5: value(0.1), pr6: value(0.5), pr7: value(0.2), pr8: value(0.8),
            rc1: value(-1), rc2: value(offset), rc3: value(0.2), rc4: value(1),
            ex1: value(-0.5), ex2: value(0.5), sm1: value(-0.2), sm2: value(0.8),
            finalGrade: value(0.4)
        )
    }

    private static func assignment(_ name: String, earned: Double?, total: Double,
                                   date: String, meta: [AssignmentMeta] = []) -> GradeInfoAssignment {
        GradeInfoAssignment(date: date, name: name, grade: earned.map { Int(($0 / total * 100).rounded()) },
                            score: earned.map { $0 / total * 100 }, pointsEarned: earned,
                            pointsTotal: total, meta: meta)
    }
}
#endif
