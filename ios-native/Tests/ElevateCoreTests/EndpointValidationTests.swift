import Testing
@testable import ElevateCore

@Suite("Skyward endpoint structure validation")
struct EndpointValidationTests {
    private let emptyGradebook = """
    <html><body>
      <h2 class="gb_heading"><a>Algebra II</a><a>Ms. Rivera</a><span class="fXs"><b>2</b></span></h2>
      <table id="grid_stuTermSummaryGrid_1">
        <thead><tr><th>Q1 Grade <span>08/12/2026 - 10/09/2026</span></th></tr></thead>
        <tbody><tr class="grade"><td>Q1</td><td></td></tr></tbody>
      </table>
      <table id="grid_stuAssignmentSummaryGrid_1"><tbody></tbody></table>
    </body></html>
    """

    private let ungradedTerm = """
    <div>
      <h2 class="gb_heading"><a>Algebra II</a><a>Ms. Rivera</a></h2>
      <div id="stuTermSummaryGrid_1"><table id="grid_stuTermSummaryGrid_1">
        <thead><tr><th>Q2 Grade <span>10/12/2026 - 12/18/2026</span></th></tr></thead>
        <tbody><tr class=""><td>&nbsp;</td><td></td></tr></tbody>
      </table></div>
      <h2 class="gb_heading">Grade Details</h2>
    </div>
    """

    @Test("A complete ungraded term response can omit the assignment grid")
    func validGridlessUngradedTerm() throws {
        let result = try SkywardGradesAPI.parseGradeInfoHTML(
            ungradedTerm, rawResponse: "<output><![CDATA[\(ungradedTerm)]]></output>"
        )
        #expect(result.course == "Algebra II")
        #expect(result.litName == "Q2")
        #expect(result.grade == nil)
        #expect(result.score == nil)
        #expect(result.gradebook.isEmpty)
    }

    @Test("An outer layout table does not turn the term header into a summary row")
    func wrappedGridlessUngradedTerm() throws {
        let html = "<table><tbody><tr><td>\(ungradedTerm)</td></tr></tbody></table>"
        let result = try SkywardGradesAPI.parseGradeInfoHTML(
            html, rawResponse: "<output><![CDATA[\(html)]]></output>"
        )
        #expect(result.litName == "Q2")
        #expect(result.gradebook.isEmpty)
        #expect(result.score == nil)
    }

    @Test("Only the complete blank two-cell summary can replace a missing assignment grid")
    func invalidGridlessTerms() {
        let malformed = [
            ungradedTerm.replacingOccurrences(of: "<td>&nbsp;</td>", with: "<td>Q2</td>"),
            ungradedTerm.replacingOccurrences(of: "<td></td>", with: "<td>94</td>"),
            ungradedTerm.replacingOccurrences(of: "<td></td>", with: "<td>Unavailable</td>"),
            ungradedTerm.replacingOccurrences(of: "<td></td>", with: ""),
            ungradedTerm.replacingOccurrences(of: "</tbody>", with: "<tr><td></td><td></td></tr></tbody>"),
            ungradedTerm.replacingOccurrences(of: "<a>Algebra II</a>", with: "<a></a>"),
            ungradedTerm.replacingOccurrences(of: "Q2 Grade ", with: ""),
            ungradedTerm + "<a id='showAssignmentInfo'>Assignment</a>",
            ungradedTerm + "<table><tr class='sf_Section cat'><td></td><td>Tests</td></tr></table>",
        ]
        for html in malformed {
            #expect(throws: SkywardError.self) {
                _ = try SkywardGradesAPI.parseGradeInfoHTML(
                    html, rawResponse: "<output><![CDATA[\(html)]]></output>"
                )
            }
        }
        for raw in [ungradedTerm, "<output><![CDATA[\(ungradedTerm)"] {
            #expect(throws: SkywardError.self) {
                _ = try SkywardGradesAPI.parseGradeInfoHTML(ungradedTerm, rawResponse: raw)
            }
        }
    }

    @Test("An ungraded term cannot hide an expired loader session")
    func expiredGridlessTerm() {
        do {
            _ = try SkywardGradesAPI.parseGradeInfoHTML(
                ungradedTerm,
                rawResponse: "<data><![CDATA[]]></data><output><![CDATA[\(ungradedTerm)]]></output>"
            )
            Issue.record("Expected session expiry")
        } catch SkywardError.sessionExpired {
            // Session validation takes precedence over a blank summary.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A structurally valid empty gradebook remains a legitimate empty result")
    func validEmptyGradebook() throws {
        let result = try SkywardGradesAPI.parseGradeInfoHTML(
            emptyGradebook,
            rawResponse: "<output><![CDATA[\(emptyGradebook)]]></output>"
        )
        #expect(result.course == "Algebra II")
        #expect(result.litName == "Q1")
        #expect(result.gradebook.isEmpty)
    }

    @Test("A populated gradebook still parses after structural validation")
    func validPopulatedGradebook() throws {
        let html = """
        <h2 class="gb_heading"><a>Algebra II</a><a>Ms. Rivera</a><span class="fXs"><b>2</b></span></h2>
        <table id="grid_stuTermSummaryGrid_1">
          <thead><tr><th>Q1 Grade</th></tr></thead>
          <tbody><tr class="grade"><td>Q1</td><td>94.5</td></tr></tbody>
        </table>
        <table id="grid_stuAssignmentSummaryGrid_1"><tbody>
          <tr class="sf_Section cat"><td></td><td style="font-weight: bold">Tests <span>weighted at 100%</span></td></tr>
          <tr><td>08/20/2026</td><td><a id="showAssignmentInfo">Unit 1</a></td><td>95</td><td>95</td><td>95 out of 100</td></tr>
        </tbody></table>
        """
        let result = try SkywardGradesAPI.parseGradeInfoHTML(html, rawResponse: html)
        #expect(result.gradebook.count == 1)
        #expect(result.gradebook.first?.assignments.first?.name == "Unit 1")
    }

    @Test("Oversized grade fields cannot overflow and zero remains valid")
    func oversizedGradeValues() throws {
        let huge = String(repeating: "9", count: 400)
        let html = """
        <h2 class="gb_heading"><a>Algebra II</a><a>Ms. Rivera</a></h2>
        <table id="grid_stuTermSummaryGrid_1">
          <thead><tr><th>Q1 Grade</th></tr></thead>
          <tbody><tr class="grade"><td>Q1</td><td>\(huge)</td></tr></tbody>
        </table>
        <table id="grid_stuAssignmentSummaryGrid_1"><tbody>
          <tr class="sf_Section cat"><td></td><td style="font-weight: bold">Tests <span>weighted at \(huge)%</span></td></tr>
          <tr><td>08/20/2026</td><td><a id="showAssignmentInfo">Zero</a></td><td>0</td><td>\(huge)</td><td>\(huge) out of \(huge)</td></tr>
        </tbody></table>
        """
        let result = try SkywardGradesAPI.parseGradeInfoHTML(html, rawResponse: html)
        #expect(result.score == nil)
        #expect(result.grade == nil)
        #expect(result.gradebook.first?.weight == nil)
        #expect(result.gradebook.first?.assignments.first?.grade == 0)
        #expect(result.gradebook.first?.assignments.first?.score == nil)
        #expect(result.gradebook.first?.assignments.first?.pointsEarned == nil)
        #expect(result.gradebook.first?.assignments.first?.pointsTotal == nil)
    }

    @Test("Scientific notation cannot be partially parsed as a grade")
    func scientificNotationGradeValues() throws {
        let html = """
        <h2 class="gb_heading"><a>Algebra II</a><a>Ms. Rivera</a></h2>
        <table id="grid_stuTermSummaryGrid_1">
          <thead><tr><th>Q1 Grade</th></tr></thead>
          <tbody><tr class="grade"><td>Q1</td><td>1e308</td></tr></tbody>
        </table>
        <table id="grid_stuAssignmentSummaryGrid_1"><tbody>
          <tr class="sf_Section cat"><td></td><td style="font-weight: bold">Tests <span>weighted at 1e308%</span></td></tr>
          <tr><td>08/20/2026</td><td><a id="showAssignmentInfo">Malformed</a></td><td>1e308</td><td>1e308</td><td>1e308 out of 1e308</td></tr>
        </tbody></table>
        """
        let result = try SkywardGradesAPI.parseGradeInfoHTML(html, rawResponse: html)
        #expect(result.score == nil)
        #expect(result.grade == nil)
        #expect(result.gradebook.first?.weight == nil)
        #expect(result.gradebook.first?.assignments.first?.grade == nil)
        #expect(result.gradebook.first?.assignments.first?.score == nil)
        #expect(result.gradebook.first?.assignments.first?.pointsEarned == nil)
        #expect(result.gradebook.first?.assignments.first?.pointsTotal == nil)
    }

    @Test("Maintenance HTML cannot become an empty gradebook")
    func malformedGradebook() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardGradesAPI.parseGradeInfoHTML(
                "<html><body>Maintenance in progress</body></html>",
                rawResponse: "<html><body>Maintenance in progress</body></html>"
            )
        }
    }

    @Test("Anchors cannot disguise malformed grade rows as an empty gradebook")
    func malformedGradeRows() {
        let html = """
        <h2 class="gb_heading"><a>Algebra II</a></h2>
        <table id="grid_stuTermSummaryGrid_1"><thead><tr><th>Q1 Grade</th></tr></thead></table>
        <table id="grid_stuAssignmentSummaryGrid_1"><tbody>
          <tr class="sf_Section cat"><td>truncated</td></tr>
        </tbody></table>
        """
        #expect(throws: SkywardError.self) {
            _ = try SkywardGradesAPI.parseGradeInfoHTML(html, rawResponse: html)
        }
    }

    @Test("Login HTML is reported as session expiry")
    func gradebookLoginPage() {
        do {
            _ = try SkywardGradesAPI.parseGradeInfoHTML(
                "<html>Family Access<form id='detailform'><input name='password'></form></html>",
                rawResponse: ""
            )
            Issue.record("Expected session expiry")
        } catch SkywardError.sessionExpired {
            // Expected typed failure.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Malformed grade CDATA is rejected")
    func malformedGradeCDATA() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardGradesAPI.extractGradeInfoHTML(from: "<output><![CDATA[<div>partial")
        }
    }

    @Test("Current gradebook requires a compatible complete student grid")
    func invalidCurrentGradebookGrid() {
        let wrongGrid = """
        <script>$.extend((sff.getValue('sf_gridObjects') || {}), {otherGrid:{tb:{r:[]}}}));</script>
        """
        let incompleteGrid = """
        <script>$.extend((sff.getValue('sf_gridObjects') || {}), {stuGradesGrid_1_2:{tb:{}}}));</script>
        """
        let malformedRows = """
        <script>$.extend((sff.getValue('sf_gridObjects') || {}), {stuGradesGrid_1_2:{tb:{r:[{}]}}}));</script>
        """
        #expect(throws: SkywardError.self) { _ = try SkywardHistoryAPI.parseGradebookHTML(wrongGrid) }
        #expect(throws: SkywardError.self) { _ = try SkywardHistoryAPI.parseGradebookHTML(incompleteGrid) }
        #expect(throws: SkywardError.self) { _ = try SkywardHistoryAPI.parseGradebookHTML(malformedRows) }
    }

    @Test("Current gradebook ignores blank and non-finite unposted scores")
    func currentGradebookRejectsNonFiniteScores() throws {
        let html = """
        <script>$.extend((sff.getValue('sf_gridObjects') || {}), {stuGradesGrid_1_2:{tb:{r:[{c:[
          {cId:'course',h:'<a data-cni="42" data-bkt="TERM 1" data-gid="GB">NaN</a>'},
          {h:'<a data-cni="42" data-bkt="TERM 2">Infinity</a>'},
          {h:'<a data-cni="42" data-bkt="TERM 3"> </a>'},
          {h:'<a data-cni="42" data-bkt="TERM 4">1e308</a>'}
        ]}]}}}));</script>
        """
        let courses = try SkywardHistoryAPI.parseGradebookHTML(html)
        #expect(courses.count == 1)
        #expect(courses.first?.course == 42)
        #expect(courses.first?.scores.isEmpty == true)
    }

    @Test("Unified history transformation keeps zero and drops non-finite scores")
    func unifiedHistoryRejectsNonFiniteScores() {
        let history: AcademicHistory = [
            "current": AcademicYear(grade: 11, courses: [
                "Biology": HistoryCourse(
                    courseName: "Biology", sm1: "Infinity", rc1: "0", rc2: "NaN"
                ),
            ]),
        ]
        let courses = UnifiedCourseTransformer.transform(history: history)
        #expect(courses.first?.currentScores == [BucketScore(bucket: "Q1", score: 0)])
        #expect(courses.first?.historicalGrades.rc1 == "0")
        #expect(courses.first?.historicalGrades.rc2 == nil)
        #expect(courses.first?.historicalGrades.sm1 == nil)
    }

    @Test("Academic history requires a compatible complete history grid")
    func invalidAcademicHistoryGrid() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory(["otherGrid": ["tb": ["r": []]]])
        }
        let blanks = (0..<16).map { _ in ["h": ""] }
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory([
                "gradeGrid_1_2_3": ["tb": ["r": [
                    ["c": [["h": "2025 - 2026 Grade 11"]]],
                    ["c": [["h": "<a>Biology</a>"], ["h": "1 - 4"]]],
                ]]],
            ])
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory([
                "gradeGrid_1_2_3": ["tb": ["r": [
                    ["c": [["h": "2025 - 2027 Grade 11"]] + blanks],
                ]]],
            ])
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory([
                "gradeGrid_1_2_3": ["tb": ["r": [
                    ["c": [["h": "2025 - 2026 Grade 99"]] + blanks],
                ]]],
            ])
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory(["gradeGrid_1_2_3": ["tb": [:]]])
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory([
                "gradeGrid_1_2_3": ["tb": ["r": [[String: Any]()]]],
            ])
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardHistoryAPI.condenseAcademicHistory([
                "gradeGrid_1_2_3": ["tb": ["r": [
                    ["c": [["h": "2025 - 2026 Grade 11"]]],
                    ["c": [[String: Any]()]],
                ]]],
            ])
        }
    }

    @Test("Pre-high-school rows are preserved for credit planning without entering the GPA subset")
    func preHighSchoolCreditSection() throws {
        let blanks = (0..<16).map { _ in ["h": ""] }
        let result = try SkywardHistoryAPI.condenseAcademicHistory([
            "gradeGrid_1_2_3": ["tb": ["r": [
                ["c": [["h": "2024 - 2025 Grade 8"]]],
                ["c": [["h": "<a>Algebra I</a>"], ["h": "1 - 4"]] + blanks],
                ["c": [["h": "2025 - 2026 Grade 9"]]],
                ["c": [["h": "<a>Biology</a>"], ["h": "1 - 4"]] + blanks],
            ]]],
        ])

        #expect(result["2024-2025"]?.courses.isEmpty == true)
        #expect(result["2024-2025"]?.planningTranscriptCourses?.first?.name == "Algebra I")
        #expect(result["2025-2026"]?.grade == 9)
        #expect(result["2025-2026"]?.courses["Biology"] != nil)
    }

    @Test("Only an explicit no-records history page is a valid gridless result")
    func verifiedEmptyAcademicHistoryPage() {
        #expect(SkywardHistoryAPI.isVerifiedEmptyAcademicHistoryPage(
            "<html><head><title>Academic History</title></head><body>No records</body></html>"
        ))
        #expect(!SkywardHistoryAPI.isVerifiedEmptyAcademicHistoryPage(
            "<html><head><title>Academic History</title></head><body>Maintenance</body></html>"
        ))
    }

    @Test("A structurally valid empty academic-history grid remains empty")
    func validEmptyAcademicHistoryGrid() throws {
        let result = try SkywardHistoryAPI.condenseAcademicHistory([
            "gradeGrid_1_2_3": ["tb": ["r": [[String: Any]]()]],
        ])
        #expect(result.isEmpty)
    }

    @Test("A structurally valid empty inbox remains empty")
    func validEmptyInbox() throws {
        let messages = try SkywardMessagesAPI.parseMessages("<ul id='messageFeed'></ul>")
        #expect(messages.isEmpty)
    }

    @Test("Skyward's capitalized MessageFeed empty state remains empty")
    func capitalizedEmptyInbox() throws {
        let html = """
        <html><body class="sf_studentAccess">
          <ul id="MessageFeed"><li class="emptyFeed">No messages...</li></ul>
        </body></html>
        """
        #expect(try SkywardMessagesAPI.parseMessages(html).isEmpty)
    }

    @Test("A capitalized feed cannot hide malformed messages or an expired session")
    func invalidCapitalizedInbox() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardMessagesAPI.parseMessages(
                "<ul id='MessageFeed'><li>Unexpected server response</li></ul>"
            )
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardMessagesAPI.parseMessages("""
            <ul id="MessageFeed"><li class="feedItem allowRemove">
              <div class="messageWrap" data-wall-id="synthetic"></div>
            </li></ul>
            """)
        }
        do {
            _ = try SkywardMessagesAPI.parseMessages("""
            <ul id="MessageFeed"><li class="emptyFeed">No messages...</li></ul>
            <p>Your session has expired</p>
            """)
            Issue.record("Expected session expiry")
        } catch SkywardError.sessionExpired {
            // Session validation takes precedence over the empty feed.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A populated inbox still parses")
    func validPopulatedInbox() throws {
        let html = """
        <ul id="messageFeed"><li class="feedItem allowRemove">
          <div class="messageWrap message_general" data-wall-id="wall-42">
            <div class="messageHead"><div class="text"></div></div>
            <div class="messageBody"><div class="date">Aug 12</div><div class="text"><div class="Subject">Welcome</div><span id="messageText_42"></span></div></div>
          </div>
        </li></ul>
        """
        let messages = try SkywardMessagesAPI.parseMessages(html)
        #expect(messages.count == 1)
        #expect(messages.first?.messageRowId == "wall-42")
        #expect(messages.first?.subject == "Welcome")
    }

    @Test("Arbitrary and login pages cannot become an empty inbox")
    func invalidInboxPages() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardMessagesAPI.parseMessages("<html><body>Service unavailable</body></html>")
        }
        #expect(throws: SkywardError.self) {
            _ = try SkywardMessagesAPI.parseMessages("<ul class='feed'></ul>")
        }
        do {
            _ = try SkywardMessagesAPI.parseMessages(
                "<html>Family Access<form id='detailform'><input name='password'></form></html>"
            )
            Issue.record("Expected session expiry")
        } catch SkywardError.sessionExpired {
            // Expected typed failure.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A truncated populated inbox is rejected")
    func truncatedInboxItem() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardMessagesAPI.parseMessages(
                "<ul id='messageFeed'><li class='feedItem allowRemove'><div class='messageWrap' data-wall-id='x'></div></li></ul>"
            )
        }
    }

    @Test("Malformed message CDATA is rejected")
    func malformedMessageCDATA() {
        #expect(throws: SkywardError.self) {
            _ = try SkywardMessagesAPI.extractMessageFragment(from: "<output><![CDATA[<li>partial")
        }
    }

    @Test("Remote message content activates only HTTPS links")
    func safeMessageLinks() {
        let rendered = SkywardMessagesAPI.renderMessageBody(
            #"<a href="javascript:alert(1)">Script</a> "#
                + #"<a href="elevate://settings">Settings</a> "#
                + #"<a href="https://school.example/path">Portal</a> "#
                + #"<span>[Dial](tel:555)</span>"#
        )
        #expect(rendered == "Script Settings [Portal](https://school.example/path) \\[Dial\\](tel:555)")
        #expect(SkywardMessagesAPI.safeMessageURL("javascript:alert(1)") == nil)
        #expect(SkywardMessagesAPI.safeMessageURL("elevate://settings") == nil)
        #expect(SkywardMessagesAPI.safeMessageURL("https://school.example/path") != nil)
    }
}
