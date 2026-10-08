import Testing
@testable import ElevateCore

@Suite("Skyward grid script extraction")
struct GridScriptTests {
    @Test("Gradebook preserves HTML entities until cell HTML is parsed")
    func encodedQuotesInGradebook() throws {
        let html = #"""
        <script>$.extend((sff.getValue('sf_gridObjects') || {}), {stuGradesGrid_1_2:{tb:{r:[{c:[
          {cId:'course',h:'<a title="Teacher&#39;s &quot;feedback&quot;" data-cni="42" data-bkt="TERM 3">90</a>'}
        ]}]}}}));</script>
        """#
        let courses = try SkywardHistoryAPI.parseGradebookHTML(html)
        #expect(courses.count == 1)
        #expect(courses.first?.course == 42)
        #expect(courses.first?.scores.first?.score == 90)
    }

    @Test("Academic history preserves quoted entities in literal strings")
    func encodedQuotesInHistory() throws {
        let html = #"""
        <script>sff.sv('sf_gridObjects', $.extend((sff.getValue('sf_gridObjects') || {}), {gradeGrid_1_2_3:{tb:{r:[{c:[{h:'<a>Teacher&#39;s &quot;course&quot;</a>'}]}]}}}));</script>
        """#
        let objects = try SkywardHistoryAPI.parseGridObjects(html: html,
            pattern: #"sff\.sv\('sf_gridObjects',\s*\$\.extend\([^,]+,\s*(\{[\s\S]*?\})\)\);"#)
        let grid = try #require(objects["gradeGrid_1_2_3"] as? [String: Any])
        let table = try #require(grid["tb"] as? [String: Any])
        let rows = try #require(table["r"] as? [[String: Any]])
        let cells = try #require(rows.first?["c"] as? [[String: Any]])
        let cellHTML = try #require(cells.first?["h"] as? String)
        #expect(cellHTML == "<a>Teacher&#39;s &quot;course&quot;</a>")
        #expect(MiniHTML.parse(cellHTML).text == "Teacher's \"course\"")
    }
}
