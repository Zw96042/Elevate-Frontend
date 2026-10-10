import XCTest
@testable import ElevateCore

final class StudentInfoTests: XCTestCase {
    private func page(photo: String = "", enrollmentGrade: String = "11") -> String {
        """
        <div class="gridWrap"><div class="sfTag"><span>Jordan &amp; Taylor</span></div>
        <div class="sf_gridTableWrap"><table id="grid_student123"><tbody><tr><td>
        <table id="grid_studentContactInfo123"><tbody><tr><td>\(photo)</td><td>
        <table id="grid_stuGridInsideGrid123"><tbody>
        <tr><td>School:</td><td>Example High School</td></tr>
        <tr><td>Call:</td><td><span>(555) 010-1234</span></td></tr>
        <tr><td>Address:</td><td><div>123 Example Road<br>Example, TX 00000</div></td></tr>
        </tbody></table></td></tr></tbody></table>
        <table id="grid_studentInfo123"><tbody>
        <tr><td>Gender:</td><td></td><td>Age (Birthday):</td><td>16 (01/01/2010)</td></tr>
        <tr><td>Language:</td><td>English</td><td>Graduation Year:</td><td>2028</td></tr>
        <tr><td>Other ID:</td><td>00123</td><td>Community Service:</td><td>0</td></tr>
        </tbody></table>
        <div class="gridWrap"><div class="sf_gridTableWrap"><table id="grid_studentEntity123_4"><tbody>
        <tr><th colspan="4" scope="col">Example High School<br><label>Phone:</label> <span>555-010-0000</span><br><label>Principal:</label> <span>Alex Example</span></th></tr>
        <tr><td>Grade:</td><td>\(enrollmentGrade)</td><td>Status:</td><td>Active</td></tr>
        <tr><td>Discipline Officer:</td><td></td><td></td><td></td></tr>
        <tr><td>Counselor:</td><td><a href="javascript:void(0)">Pat Example</a></td><td></td><td></td></tr>
        </tbody></table></div></div>
        </td></tr></tbody></table></div></div>
        <table id="grid_familyContact999"><tr><td>Private guardian details ignored</td></tr></table>
        """
    }

    func testVerifiedStructureKeepsOfficialEnrollmentGradeAndContact() throws {
        let data = try SkywardStudentInfoAPI.parse(page(enrollmentGrade: "Grade 11"))
        XCTAssertEqual(data.name, "Jordan & Taylor")
        XCTAssertEqual(data.contactFields.first(where: { $0.label == "Call:" })?.value, "(555) 010-1234")
        XCTAssertEqual(data.contactFields.first(where: { $0.label == "Address:" })?.value, "123 Example Road\nExample, TX 00000")
        XCTAssertEqual(data.enrollments.first?.schoolName, "Example High School")
        XCTAssertEqual(data.enrollments.first?.fields.first(where: { $0.label == "Grade:" })?.value, "Grade 11")
        XCTAssertEqual(data.enrollments.first?.fields.first(where: { $0.label == "Phone:" })?.value, "555-010-0000")
        XCTAssertEqual(data.studentFields.first(where: { $0.label == "Gender:" })?.value, "")
        XCTAssertNil(data.photoData)
        XCTAssertFalse(data.photoLoadFailed)
    }

    func testPhotoSourceIsTransientAndNeverEncoded() throws {
        let source = "qdirconfig123.p?StuPic=1&amp;duserid=synthetic&amp;dwd=synthetic&amp;pEnc=synthetic&amp;rev=1"
        let parsed = try SkywardStudentInfoAPI.parsePage(page(photo: "<img src='\(source)'>"))
        XCTAssertNotNil(parsed.photoPath)
        let encoded = String(decoding: try JSONEncoder().encode(parsed.data), as: UTF8.self)
        XCTAssertFalse(encoded.contains("qdirconfig"))
        XCTAssertFalse(encoded.contains("synthetic"))
    }

    func testContactIconsDoNotMakeTheStudentPhotoAmbiguous() throws {
        let photo = "qdirconfig123.p?StuPic=1&duserid=synthetic"
        let images = "<img src='phone.png'><img src='map.png'><img src='\(photo)'>"
        let parsed = try SkywardStudentInfoAPI.parsePage(page(photo: images))
        XCTAssertEqual(parsed.photoPath, photo)
        XCTAssertEqual(parsed.data.name, "Jordan & Taylor")
        XCTAssertEqual(parsed.data.enrollments.first?.fields.first(where: { $0.label == "Grade:" })?.value, "11")
    }

    func testDecorativeImagesWithoutAStudentPhotoStillLoadProfile() throws {
        let parsed = try SkywardStudentInfoAPI.parsePage(page(photo: "<img src='phone.png'><img src='map.png'>"))
        XCTAssertNil(parsed.photoPath)
        XCTAssertFalse(parsed.data.contactFields.isEmpty)
    }

    func testRepeatedSameStudentPhotoHasOneLocation() throws {
        let photo = "qdirconfig123.p?StuPic=1&duserid=synthetic"
        let parsed = try SkywardStudentInfoAPI.parsePage(page(photo: "<img src='\(photo)'><img src='\(photo)'>"))
        XCTAssertEqual(parsed.photoPath, photo)
    }

    func testDistinctStudentPhotosRemainAmbiguous() {
        let images = "<img src='qdirconfig123.p?StuPic=1'><img src='qdirconfig456.p?StuPic=1'>"
        XCTAssertThrowsError(try SkywardStudentInfoAPI.parsePage(page(photo: images)))
    }

    func testMissingOptionalSectionsAreNotInvented() throws {
        let html = "<div><div class='sfTag'><span>Example Student</span></div><div class='sf_gridTableWrap'><table id='grid_student1'><tr><td></td></tr></table></div></div>"
        let data = try SkywardStudentInfoAPI.parse(html)
        XCTAssertTrue(data.contactFields.isEmpty)
        XCTAssertTrue(data.studentFields.isEmpty)
        XCTAssertTrue(data.enrollments.isEmpty)
    }

    func testMalformedAndAmbiguousResponsesFail() {
        for html in [page().replacingOccurrences(of: "</td>", with: "", range: page().range(of: "</td>")),
                     String(page().prefix(page().count / 2)), page() + page(),
                     "<html><title>Student Info</title><body>Maintenance</body></html>",
                     page().replacingOccurrences(of: "Jordan &amp; Taylor", with: "Student Info")] {
            XCTAssertThrowsError(try SkywardStudentInfoAPI.parse(html))
        }
    }

    func testUnrecognizedEnrollmentHeadersAndMalformedRowsFail() {
        for html in [page().replacingOccurrences(of: "colspan=\"4\"", with: "colspan=\"3\""),
                     page().replacingOccurrences(of: "<th colspan=\"4\" scope=\"col\">", with: "<td colspan=\"4\">"),
                     page().replacingOccurrences(of: "<td>Status:</td><td>Active</td>", with: "<th>Status:</th><td>Active</td>"),
                     page().replacingOccurrences(of: "<span>Alex Example</span>", with: "") ] {
            XCTAssertThrowsError(try SkywardStudentInfoAPI.parse(html))
        }
    }

    func testOmittedTbodyClosingIsAccepted() throws {
        XCTAssertNoThrow(try SkywardStudentInfoAPI.parse(page().replacingOccurrences(of: "</tbody>", with: "")))
    }

    func testExpiredSessionIsNotAProfile() {
        XCTAssertThrowsError(try SkywardStudentInfoAPI.parse("Your session has expired")) { error in
            guard case SkywardError.sessionExpired = error else { return XCTFail("Expected session expiry") }
        }
    }

    func testOlderCacheDefaultsPhotoFailureFlag() throws {
        let json = #"{"name":"Example Student","contactFields":[],"studentFields":[],"enrollments":[]}"#
        let data = try JSONDecoder().decode(StudentInfoData.self, from: Data(json.utf8))
        XCTAssertNil(data.photoData)
        XCTAssertFalse(data.photoLoadFailed)
    }
}
