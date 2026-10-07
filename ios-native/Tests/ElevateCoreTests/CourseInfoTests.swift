import Foundation
import Testing
@testable import ElevateCore

struct CourseInfoTests {
    private var course: GradebookCourse {
        GradebookCourse(course: 101, courseName: "INDEPENDENT STUDY IN ENGLISH (",
            instructor: "Synthetic Teacher", period: 1, scores: [],
            stuId: "1001", corNumId: 101, section: "2", gbId: "3001")
    }

    private func page(student: String = "1001", number: String = "101", section: String = "sff.getValue('section')",
                      extra: String = "") -> String {
        """
        <table id="classDesc_1001_101_0_2"><tr><td><span class="bld classDesc"><a name="syntheticCourse">INDEPENDENT STUDY IN ENGLISH (</a></span></td></tr></table>
        <script>
        sff.bind('syntheticCourse','click',function(e){sff.load('sfdialogs.w',{'action':'dialog','type':'class','student':'\(student)','eid':'070','cornumid':'\(number)','track':'0','section':\(section)\(extra)},function(r){});});
        </script>
        """
    }

    @Test("Course popup fields bind only the matching student, course, and section")
    func requestIdentity() throws {
        let fields = Dictionary(uniqueKeysWithValues: try SkywardCourseInfoAPI.requestFields(html: page(), course: course))
        #expect(fields["student"] == "1001")
        #expect(fields["cornumid"] == "101")
        #expect(fields["section"] == "2")
        #expect(fields["type"] == "class")
        #expect(fields["action"] == "dialog")
        for malformed in [page(student: "1002"), page(number: "102"), page(section: "'3'"),
                          page(section: "executeSomething()"), page(extra: ", 'unknown':'value'"),
                          page().replacingOccurrences(of: "syntheticCourse','click", with: "unrelatedCourse','click")] {
            #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.requestFields(html: malformed, course: course) }
        }
    }

    @Test("Conflicting handlers and executable literals cannot supply a catalog request")
    func boundedHandler() {
        let conflicting = page() + page(number: "102")
        #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.requestFields(html: conflicting, course: course) }
        let expression = page().replacingOccurrences(of: "'track':'0'", with: "'track':run()")
        #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.requestFields(html: expression, course: course) }
        #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.requestFields(html: String(repeating: "x", count: 2_000_001), course: course) }
    }

    @Test("Skyward CSS ID bindings resolve only the matching course popup")
    func cssIDBinding() throws {
        let bound = page().replacingOccurrences(of: "sff.bind('syntheticCourse','click'",
            with: "sff.aee(\"click\",\"#syntheticCourse\"")
        let fields = Dictionary(uniqueKeysWithValues: try SkywardCourseInfoAPI.requestFields(html: bound, course: course))
        #expect(fields["cornumid"] == "101")
        #expect(fields["section"] == "2")
        for otherSelector in ["#syntheticCourseOther", "#otherCourse", ".syntheticCourse"] {
            let unrelated = bound.replacingOccurrences(of: "\"#syntheticCourse\"", with: "\"\(otherSelector)\"")
            #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.requestFields(html: unrelated, course: course) }
        }
        let unrelatedHandler = bound.replacingOccurrences(of: "\"#syntheticCourse\"", with: "\"#otherCourse\"")
            .replacingOccurrences(of: "'cornumid':'101'", with: "'cornumid':'102'")
        let additionalScript = "<script>" + unrelatedHandler.components(separatedBy: "<script>")[1]
        #expect(try SkywardCourseInfoAPI.requestFields(html: bound + additionalScript, course: course).count == fields.count)
    }

    @Test("Course popup preserves Skyward's bounded dialogOptions field")
    func dialogOptionsField() throws {
        let html = page(extra: ", 'dialogOptions':'syntheticOptions'")
            .replacingOccurrences(of: "'syntheticCourse','click'", with: "'#syntheticCourse','click'")
        let fields = Dictionary(uniqueKeysWithValues: try SkywardCourseInfoAPI.requestFields(html: html, course: course))
        #expect(fields["dialogOptions"] == "syntheticOptions")
        #expect(fields["cornumid"] == "101")
        for value in ["{}", "run()", "'" + String(repeating: "x", count: 129) + "'"] {
            let malformed = page(extra: ", 'dialogOptions':" + value)
            #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.requestFields(html: malformed, course: course) }
        }
    }

    @Test("Catalog code cells remain data and reject ambiguous or absent identities")
    func catalogCells() throws {
        #expect(try SkywardCourseInfoAPI.parseCatalogCode("<table><tr><td>Course:</td><td>LA145 - 2</td></tr></table>") == "LA145")
        #expect(try SkywardCourseInfoAPI.parseCatalogCode("<table><tr><td>Course:</td><td>LA145 / 2</td></tr></table>") == "LA145")
        #expect(try SkywardCourseInfoAPI.parseCatalogCode("<table><tr><td>LA146</td><td>LA146</td></tr></table>") == "LA146")
        for bad in ["<script>var course='LA145';</script>", "<td>LA145</td><td>LA147</td>",
                    "<td>Unknown</td>", "<td>LA145 extra</td>", String(repeating: "x", count: 256_001)] {
            #expect(throws: (any Error).self) { try SkywardCourseInfoAPI.parseCatalogCode(bad) }
        }
    }

    @Test("Only exact incomplete Independent Study labels need catalog lookups")
    func selectiveLookup() {
        #expect(SkywardCourseInfoAPI.needsCatalogCode("Independent Study in English ("))
        for name in ["Independent Study in English (1)", "Independent Study in English III", "AP Seminar", "English", "Independent Study"] {
            #expect(!SkywardCourseInfoAPI.needsCatalogCode(name))
        }
    }
}
