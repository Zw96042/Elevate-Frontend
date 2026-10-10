import Foundation
import WidgetKit
import UIKit

#if DEBUG
enum SampleData {
    private static let studentID = "sample-student"

    static let fees = FeesData(fees: [
        FeeRecord(id: "sample-fee-1", description: "Lab supplies", schoolYear: "2026-2027", date: "08/15/2026", fields: [
            FeeField(label: "School year", value: "2026-2027"), FeeField(label: "Due date", value: "08/15/2026"),
            FeeField(label: "Amount charged", value: "$30.00"), FeeField(label: "Amount paid", value: "$10.00"),
            FeeField(label: "Amount due", value: "$20.00"), FeeField(label: "Remaining due", value: "$20.00"),
            FeeField(label: "Payor name", value: "Jordan Avery"), FeeField(label: "Pay plan ID", value: ""),
        ]),
        FeeRecord(id: "sample-fee-2", description: "AP exam deposit", schoolYear: "2026-2027", date: "10/20/2026", fields: [
            FeeField(label: "School year", value: "2026-2027"), FeeField(label: "Due date", value: "10/20/2026"),
            FeeField(label: "Amount charged", value: "$40.00"), FeeField(label: "Amount paid", value: "$0.00"),
            FeeField(label: "Amount due", value: "$40.00"), FeeField(label: "Remaining due", value: "$40.00"),
        ]),
    ], payments: [
        FeeRecord(id: "sample-payment-1", description: "Activity fee payment", schoolYear: "2026-2027", date: "09/15/2026", fields: [
            FeeField(label: "Payor name", value: "Jordan Avery"), FeeField(label: "School year", value: "2026-2027"),
            FeeField(label: "Payment date", value: "09/15/2026"), FeeField(label: "Payment amount", value: "$10.00"),
            FeeField(label: "Check number", value: ""), FeeField(label: "Receipt number", value: "SAMPLE-01"),
        ]),
    ])

    static var studentInfo: StudentInfoData {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            UIImage(systemName: "person.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 40, y: 28, width: 80, height: 104))
        }.pngData()
        return StudentInfoData(name: "Avery, Jordan", contactFields: [
            StudentInfoField(label: "School:", value: "Example High School"),
            StudentInfoField(label: "Call:", value: "512-555-0123"),
            StudentInfoField(label: "Address:", value: "123 Example Street\nAustin, TX 78701"),
        ], studentFields: [
            StudentInfoField(label: "Gender:", value: "Not provided"),
            StudentInfoField(label: "Age (Birthday):", value: "17 (03/17/2009)"),
            StudentInfoField(label: "Language:", value: "English"),
            StudentInfoField(label: "Graduation Year:", value: "2027"),
            StudentInfoField(label: "Other ID:", value: "SAMPLE-001"),
            StudentInfoField(label: "Community Service:", value: "12 hours"),
        ], enrollments: [
            StudentEnrollment(id: "sample-enrollment", schoolName: "Example High School", fields: [
                StudentInfoField(label: "Grade:", value: "12"), StudentInfoField(label: "Status:", value: "Active"),
                StudentInfoField(label: "Phone:", value: "512-555-0100"),
                StudentInfoField(label: "Principal:", value: "Reed, Taylor"),
                StudentInfoField(label: "Counselor:", value: "Morgan, Alex"),
            ]),
        ], photoData: photo)
    }

    static var documentResource: SkywardBinaryHTTP.Resource {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            ("Example High School\nQuarter 1 report card\nAvery, Jordan\n\nMathematics   93\nEnglish   96" as NSString).draw(at: CGPoint(x: 48, y: 48), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        return SkywardBinaryHTTP.Resource(data: data, mimeType: "application/pdf")
    }

    static let documents = DocumentsData(documents: [
        SkywardDocument(id: "sample-report-1", title: "Quarter 1 report card", kind: "Report card", created: "10/02/2026"),
        SkywardDocument(id: "sample-report-2", title: "Spring semester report card", kind: "Report card", created: "05/28/2026"),
        SkywardDocument(id: "sample-document-1", title: "Enrollment confirmation", kind: "Document", created: "08/01/2026"),
    ])

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
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-CurrentSportsPreview"), result.count >= 8 {
            result[6].courseName = "TRACK AND FIELD"
            result[7].courseName = "SPORTS MEDICINE"
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-FutureQuarterPreview") {
            for index in result.indices {
                result[index].currentScores.removeAll { ["Q2", "Q3", "Q4"].contains($0.bucket) }
                if result[index].gradeYear == 12 {
                    result[index].historicalGrades.rc2 = nil
                    result[index].historicalGrades.rc3 = nil
                    result[index].historicalGrades.rc4 = nil
                }
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

    static let attendance = AttendanceData(records: [
        AttendanceRecord(id: "sample-calendar-attendance", date: "2026-09-16", attendance: "Medical appointment",
                         period: "1", courseName: "LINEAR ALGEBRA", granularity: .period),
        AttendanceRecord(id: "sample-attendance-1", date: "2026-09-30", attendance: "Tardy",
                         period: "2", courseName: "MULTIVARIABLE CALCULUS", granularity: .period),
        AttendanceRecord(id: "sample-attendance-2", date: "2026-09-18", attendance: "Medical appointment",
                         period: "1", courseName: "LINEAR ALGEBRA", granularity: .period),
        AttendanceRecord(id: "sample-attendance-3", date: "2026-09-18", attendance: "Medical appointment",
                         period: "2", courseName: "MULTIVARIABLE CALCULUS", granularity: .period),
        AttendanceRecord(id: "sample-attendance-4", date: "2026-09-03", attendance: "School activity",
                         period: "All Day", courseName: nil, granularity: .daily),
    ])

    /// Calendar-only source fixtures; grade and what-if fixtures remain separate.
    static func calendar(term: TermLabel, courses: [UnifiedCourseData]) -> SchoolCalendarData {
        let eligible = SchoolCalendar.eligibleCourses(courses, term: term)
        let sourceDate: String
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-FollowupPreview") {
            sourceDate = SchoolWeek.day(for: Date())
        } else {
            switch term {
            case .q2: sourceDate = "11/16/26"
            case .q3: sourceDate = "2/16/27"
            case .q4: sourceDate = "4/16/27"
            default: sourceDate = "9/16/26"
            }
        }
        // Rows near each quarter's start, so the week strip around October 9,
        // 2026 shows Q1 work and Q2 work appearing once Q2 loads.
        let nearDate: String
        switch term {
        case .q2: nearDate = "10/14/26"
        case .q3: nearDate = "1/6/27"
        case .q4: nearDate = "3/24/27"
        default: nearDate = "10/7/26"
        }
        let now = Date()
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-FutureQuarterPreview"), term == .q2 {
            return SchoolCalendarData(term: term, assignments: [], updatedAt: now,
                                      eligibleCourseCount: eligible.count, resolvedCourseIDs: Set(eligible.map(\.id)))
        }
        let snapshots = eligible.enumerated().map { index, course in
            let assignments: [GradeInfoAssignment]
            switch index {
            case 0:
                assignments = [
                    assignment("Matrix practice due", earned: 0, total: 10, date: sourceDate),
                    assignment("Practice check", earned: nil, total: 10, date: sourceDate),
                    assignment("Practice check", earned: nil, total: 10, date: sourceDate),
                    assignment("Date pending from Skyward", earned: nil, total: 10, date: "2/30/26"),
                    assignment("Chapter review", earned: nil, total: 15, date: nearDate),
                    assignment("Lab notebook check", earned: nil, total: 10, date: nearDate),
                ]
            case 1:
                assignments = [assignment("Reading response due", earned: nil, total: 20, date: sourceDate,
                                          meta: [.init(type: "missing", note: "Missing")]),
                               assignment("Reading log", earned: nil, total: 10, date: nearDate)]
            case 2:
                assignments = [assignment("An extended source assignment title for the investigation and reflection on laboratory measurement uncertainty",
                                          earned: nil, total: 20, date: sourceDate,
                                          meta: [.init(type: "noCount", note: "No count")])]
            default: assignments = []
            }
            let result = GradeInfoResult(course: course.courseName, instructor: course.instructor ?? "",
                period: course.period, litName: term.bucket,
                gradebook: [GradeCategory(category: "Assignments", assignments: assignments)], score: nil, grade: nil)
            return SchoolCalendarCourseSnapshot(course: course,
                assignments: CalendarAssignment.sourceAssignments(course: course, term: term, gradeInfo: result),
                updatedAt: now, isResolved: true, didFail: false)
        }
        return SchoolCalendarData(term: term, snapshots: snapshots)
    }

    /// Explicit debug-only journal fixtures, never observations of a real account.
    static func installFollowupHistory(courses: [UnifiedCourseData]) {
        guard ProcessInfo.processInfo.arguments.contains("-SampleData"),
              ProcessInfo.processInfo.arguments.contains("-FollowupPreview"),
              !UserDefaults.standard.bool(forKey: "account.sample.followupHistorySeeded"),
              let original = SchoolCalendar.eligibleCourses(courses, term: .q1).first else { return }
        let journal = GradeJournalStore(accountIdentifier: "sample")
        let earlier = Date().addingTimeInterval(-3_600)
        journal.observeCourseAverages(courses: [original], at: earlier, expectedAccountIdentifier: "sample")
        var changed = original
        if let index = changed.currentScores.firstIndex(where: { $0.bucket == "Q1" }) {
            changed.currentScores[index].score += 1.25
        }
        journal.observeCourseAverages(courses: [changed], expectedAccountIdentifier: "sample")
        var info = GradeInfoResult(course: original.courseName, instructor: "Synthetic teacher", litName: "TERM 3",
            gradebook: [.init(category: "Daily", assignments: [
                .init(date: SchoolWeek.day(for: Date()), name: "Synthetic practice", pointsEarned: 8, pointsTotal: 10,
                      meta: [.init(type: "missing", note: "Missing")])
            ])])
        journal.observeAssignments(info, courseID: original.id, courseName: original.courseName, term: .q1,
            at: earlier, expectedAccountIdentifier: "sample")
        info.gradebook[0].assignments[0].pointsEarned = 10
        info.gradebook[0].assignments[0].meta = []
        journal.observeAssignments(info, courseID: original.id, courseName: original.courseName, term: .q1,
            expectedAccountIdentifier: "sample")
        UserDefaults.standard.set(true, forKey: "account.sample.followupHistorySeeded")
    }

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
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-FutureQuarterPreview"), scoreBucket == "Q2" {
            return GradeInfoResult(course: course.courseName, instructor: course.instructor ?? "",
                                   period: course.period, litName: params.bucket, gradebook: [], score: nil, grade: nil)
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-AssignmentRoutingPreview"),
           let term = SchoolCalendar.quarters.first(where: { $0.bucket == params.bucket }) {
            let rows = calendar(term: term, courses: courses).assignments.filter { $0.course.id == course.id }
            return GradeInfoResult(course: course.courseName, instructor: course.instructor ?? "",
                period: course.period, litName: params.bucket,
                gradebook: [GradeCategory(category: "Assignments", weight: 100, assignments: rows.map {
                    assignment($0.title, earned: nil, total: 10, date: $0.sourceDate, meta: $0.meta)
                })], score: nil, grade: nil)
        }

        let isEmpty = ProcessInfo.processInfo.arguments.contains("-EmptyAssignments")
        var result = GradeInfoResult(
            course: course.courseName,
            instructor: course.instructor ?? "",
            period: course.period,
            litName: params.bucket,
            litBegin: "8/1/26",
            litEnd: "10/25/26",
            gradebook: isEmpty ? [] : [
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
            score: isEmpty ? nil : score,
            grade: isEmpty ? nil : score.map { Int($0.rounded()) }
        )
        if !isEmpty, ProcessInfo.processInfo.arguments.contains("-ScoreLayoutSamples") {
            result.gradebook[0].assignments += [
                assignment("Score layout full points", earned: 100, total: 100, date: "8/10/26"),
                GradeInfoAssignment(date: "8/9/26", name: "Score layout bonus points",
                                    grade: nil, score: nil, pointsEarned: 2, pointsTotal: 0, meta: []),
                assignment("An extended assignment name to verify readable editable score alignment",
                           earned: 12.5, total: 15, date: "8/8/26"),
            ]
        }
        if !isEmpty, ProcessInfo.processInfo.arguments.contains("-DecimalScorePreview") {
            result.gradebook[0].assignments[0].pointsEarned = 19.1234
            result.gradebook[0].assignments[0].score = 19.1234
            result.score = 93.2789
        }
        if !isEmpty, ProcessInfo.processInfo.arguments.contains("-WeightedContributionPreview") {
            // Synthetic half-cent ties distinguish contribution rounding from
            // rounding category averages or only the final total.
            result.gradebook = [
                GradeCategory(category: "Practice", weight: 50, adjustedWeight: 50, assignments: [
                    assignment("Contribution practice", earned: 90.01, total: 100, date: "8/7/26"),
                ]),
                GradeCategory(category: "Assessments", weight: 50, adjustedWeight: 50, assignments: [
                    assignment("Contribution assessment", earned: 94.01, total: 100, date: "8/6/26"),
                ]),
            ]
            result.score = 92.02
            result.grade = 92
        }
        return result
    }

    /// Exercises the real iOS reminder callback using only the synthetic account.
    @MainActor
    static func scheduleNotificationTapPreview(courses: [UnifiedCourseData]) async {
        guard ProcessInfo.processInfo.arguments.contains("-SampleData"),
              ProcessInfo.processInfo.arguments.contains("-NotificationTapPreview"),
              SchoolNotifications.shared.accountScope == "sample",
              let course = courses.first(where: { $0.gradeYear == 12 }) else { return }
        let notifications = SchoolNotifications.shared
        await notifications.setRemindersEnabled(true)
        _ = await notifications.saveReminder(course: course, term: .q1, assignmentID: nil,
            title: "Notification tap regression", fireDate: Date().addingTimeInterval(12),
            expectedAccountScope: "sample")
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
            courseId: gradeYear == 12 ? 10_000 + index : nil,
            corNumId: gradeYear == 12 ? "sample-\(gradeYear)-\(index)" : "",
            stuId: gradeYear == 12 ? studentID : "",
            section: gradeYear == 12 ? "S\(index)" : "",
            gbId: gradeYear == 12 ? "GB\(index)" : "",
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
            historicalGrades: history(score: score, offset: offset),
            academicYear: "\(2023 + gradeYear - 9)-\(2024 + gradeYear - 9)",
            historyRowKey: "sample-\(gradeYear)-\(index)",
            academicYearIsVerified: true,
            currentAcademicYearIsVerified: gradeYear == 12 && !ProcessInfo.processInfo.arguments.contains("-HistoryYearUnknownPreview"),
            isTranscriptRecord: gradeYear != 12,
            isCurrentEnrollment: gradeYear == 12,
            currentEnrollmentSemester: gradeYear == 12 ? .fall : nil,
            currentEnrollmentGradeYear: gradeYear == 12 ? gradeYear : nil,
            currentEnrollmentObservedAt: gradeYear == 12 ? Date() : nil
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
