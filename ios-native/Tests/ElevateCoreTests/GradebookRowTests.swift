import Foundation
import Testing
@testable import ElevateCore

@Suite("Gradebook row ownership")
struct GradebookRowTests {
    @Test("Current gradebook source establishes membership and scored semester, not a future blank semester")
    func enrollmentSourceSemesters() throws {
        let html = """
        <p>Grade 11</p>
        <table id="classDesc_7_42_0_1"><tr><td><span class="bld classDesc"><a>English III</a></span></td></tr></table>
        <script>$.extend((sff.getValue('sf_gridObjects') || {}), {stuGradesGrid_1_2:{tb:{r:[{c:[
          {cId:'course',h:'<a data-cni="42" data-bkt="TERM 3" data-gid="GB">55</a>'},
          {h:'<a data-cni="42" data-bkt="TERM 9"> </a>'},
          {h:'<a data-cni="42" data-bkt="SEM 2"> </a>'}
        ]}]}}}));</script>
        """
        let rows = try SkywardHistoryAPI.parseGradebookHTML(html)
        let observedAt = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
        let combined = SkywardHistoryAPI.combine(history: [:], gradebook: rows,
            fallbackGrade: SkywardHistoryAPI.inferGradeLevel(from: html), observedAt: observedAt)
        let courses = UnifiedCourseTransformer.transform(history: combined)
        #expect(courses.first?.hasGradebookParams == true)
        #expect(courses.first?.isCurrentEnrollment == true)
        #expect(courses.first?.currentEnrollmentSemester == .fall)
        #expect(CoursePlanner.calculate(plan: CoursePlan(), officialCourses: courses, asOf: observedAt).currentTotal == 0.5)
        let blank = html.replacingOccurrences(of: ">55</a>", with: "> </a>")
        let blankRows = try SkywardHistoryAPI.parseGradebookHTML(blank)
        let unknown = UnifiedCourseTransformer.transform(history: SkywardHistoryAPI.combine(history: [:], gradebook: blankRows,
            fallbackGrade: 11, observedAt: observedAt))
        #expect(unknown.first?.isCurrentEnrollment == true)
        #expect(unknown.first?.currentEnrollmentSemester == nil)
        #expect(CoursePlanner.calculate(plan: CoursePlan(), officialCourses: unknown, asOf: observedAt).currentTotal == 0)
    }

    @Test("Skyward's full-width there-are-no-assignments row is a verified empty result")
    func emptyAssignmentPlaceholder() throws {
        let html = """
        <h2 class="gb_heading"><a>Example course</a></h2>
        <table id="grid_stuTermSummaryGrid_1">
          <thead><tr><th>Q1 Grade</th></tr></thead>
          <tbody><tr class="grade"><td>Q1</td><td></td></tr></tbody>
        </table>
        <table id="grid_stuAssignmentSummaryGrid_1"><tbody>
          <tr><td colspan="9">There are no daily assignments</td></tr>
        </tbody></table>
        """
        let result = try SkywardGradesAPI.parseGradeInfoHTML(html, rawResponse: html)
        #expect(result.gradebook.isEmpty)
        #expect(result.score == nil)
        for replacement in [
            "<td colspan='9'>Temporarily unavailable</td>",
            "<td>There are no daily assignments</td>",
            "<td colspan='9'><a>There are no daily assignments</a></td>",
            "<td>There are no daily assignments</td><td>Truncated data</td>",
            "<td colspan='9'><a id='showAssignmentInfo'>There are no daily assignments</a></td>",
        ] {
            let malformed = html.replacingOccurrences(of: "<td colspan=\"9\">There are no daily assignments</td>", with: replacement)
            #expect(throws: SkywardError.self) {
                _ = try SkywardGradesAPI.parseGradeInfoHTML(malformed, rawResponse: malformed)
            }
        }
    }

    @Test("Layout table ancestors cannot pull a grid header into assignment rows")
    func wrappedDivGrid() throws {
        let html = """
        <table><tbody><tr><td>
          <h2 class="gb_heading"><a>Example course</a><a>Example teacher</a></h2>
          <table id="grid_stuTermSummaryGrid_1">
            <thead><tr><th>Q1 Grade</th></tr></thead>
            <tbody>
              <tr><td colspan="2"></td></tr>
              <tr class="grade"><td>Q1</td><td>94</td></tr>
            </tbody>
          </table>
          <div id="stuAssignmentSummaryGrid_1"><table>
            <thead><tr><th>Date</th><th>Assignment</th><th>Grade</th></tr></thead>
            <tbody>
              <tr><td colspan="9">There are no daily assignments</td></tr>
              <tr class="sf_Section cat"><td></td><td>Tests <span>weighted at 100%</span></td></tr>
              <tr><td>09/01/2026</td><td><a id="showAssignmentInfo">Example test</a></td><td>94</td><td>94</td><td>94 out of 100</td></tr>
            </tbody>
          </table></div>
        </td></tr></tbody></table>
        """
        let result = try SkywardGradesAPI.parseGradeInfoHTML(html, rawResponse: html)
        #expect(result.score == 94)
        #expect(result.gradebook.count == 1)
        #expect(result.gradebook.first?.assignments.count == 1)
        #expect(result.gradebook.first?.assignments.first?.name == "Example test")
    }
}
