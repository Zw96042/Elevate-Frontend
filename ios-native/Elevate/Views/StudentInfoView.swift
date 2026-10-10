import SwiftUI
import UIKit

/// The student's own profile as Skyward lists it: photo, name, each school
/// enrollment (the official grade comes only from there), and the student's
/// contact and student fields. Read-only, and limited to the student;
/// family and guardian details are never shown.
struct StudentInfoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var photoWidth: CGFloat = 76
    @State private var showingConnect = false

    var body: some View {
        Group {
            if store.canShowData {
                content
            } else {
                LoginPromptView(message: "Connect your Skyward account to see your student information from your school.") {
                    showingConnect = true
                }
                .softScrollEdges()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Student Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("studentInfo.screen")
        .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
        .task(id: store.accountRevision) {
            guard store.canShowData else { return }
            await store.refreshStudentInfo()
        }
    }

    /// Never taller than this, so the photo stays a portrait beside or
    /// above the name rather than filling the screen at large text sizes.
    private var shownPhotoWidth: CGFloat { min(photoWidth, 140) }

    private var content: some View {
        let hasData = store.studentInfo != nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    lastUpdated: store.studentInfoLastUpdated,
                    isRefreshing: store.studentInfoLoading && hasData,
                    error: hasData ? store.studentInfoError : nil
                ) {
                    await store.refreshStudentInfo(force: true)
                }
                .padding(.horizontal, Metrics.page)

                if let info = store.studentInfo {
                    profile(info)
                } else if let error = store.studentInfoError {
                    InlineErrorState(title: "Couldn't load student info", message: error) {
                        await store.refreshStudentInfo(force: true)
                    }
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 12)
                    .accessibilityIdentifier("studentInfo.error")
                } else {
                    // Nothing fetched or saved yet, including before the
                    // first request starts.
                    loadingProfile
                }
            }
            .padding(.bottom, 32)
        }
        .softScrollEdges()
        .visibleRefreshable {
            await store.refreshStudentInfo(force: true)
        }
    }

    private func profile(_ info: StudentInfoData) -> some View {
        let sections = ProfileSection.sections(from: info)
        return VStack(alignment: .leading, spacing: 0) {
            StudentHeader(info: info, photoWidth: shownPhotoWidth)
                .padding(.top, 8)

            if sections.isEmpty {
                EmptyStateView(
                    title: "No other details",
                    message: "Skyward lists no contact, student, or enrollment details for this account."
                )
                .padding(.top, 12)
                .accessibilityIdentifier("studentInfo.empty")
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        GroupLabel(section.title)
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { index, line in
                            if index > 0 { InsetDivider() }
                            SourceFieldLine(label: line.label, value: line.value)
                                .accessibilityIdentifier("\(section.id).field.\(index)")
                        }
                    }
                    .padding(.top, Metrics.sectionGap)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(section.id)
                }
            }
        }
        .padding(.horizontal, Metrics.page)
    }

    /// The profile's shape: the photo frame beside the name, then labelled
    /// sections of source fields, each a label leading and its value trailing.
    private var loadingProfile: some View {
        // Label and value lengths, in figures, for each placeholder section.
        let sections: [[(label: Int, value: Int)]] = [
            [(10, 6), (8, 12), (12, 9), (9, 14)],
            [(6, 13), (5, 17), (8, 10)],
        ]
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        photoPlaceholder
                        SkeletonText(.title2.bold(), length: 10)
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        photoPlaceholder
                        SkeletonText(.title2.bold(), length: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 8)

            ForEach(sections.indices, id: \.self) { section in
                VStack(alignment: .leading, spacing: 0) {
                    SkeletonText(.footnote.weight(.medium), length: 9, tone: .secondary)
                        .padding(.bottom, 2)
                    ForEach(sections[section].indices, id: \.self) { index in
                        if index > 0 { InsetDivider() }
                        fieldPlaceholder(sections[section][index])
                    }
                }
                .padding(.top, Metrics.sectionGap)
            }
        }
        .padding(.horizontal, Metrics.page)
        .loadingPlaceholder("Loading student info")
        .accessibilityIdentifier("studentInfo.loading")
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            .fill(Color.well)
            .frame(width: shownPhotoWidth, height: shownPhotoWidth * 4 / 3)
    }

    /// `SourceFieldLine`'s shape: the muted label leading and the value
    /// trailing, or the value beneath its label at accessibility sizes.
    private func fieldPlaceholder(_ lengths: (label: Int, value: Int)) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    SkeletonText(.subheadline, length: lengths.label, tone: .secondary)
                    SkeletonText(.body, length: lengths.value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    SkeletonText(.body, length: lengths.label, tone: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SkeletonText(.body, length: lengths.value)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

/// A group of the student's own source fields under a quiet label.
private struct ProfileSection: Identifiable {
    struct Line {
        var label: String
        var value: String
    }

    var id: String
    var title: String
    var lines: [Line]

    /// Enrollments first, since they carry the official grade, then the
    /// student's contact and student fields, each in Skyward's order.
    static func sections(from info: StudentInfoData) -> [ProfileSection] {
        var sections: [ProfileSection] = []
        for (index, enrollment) in info.enrollments.enumerated() where !enrollment.fields.isEmpty {
            let school = enrollment.schoolName.flatMap(SourceFieldText.value)
            sections.append(ProfileSection(
                id: "studentInfo.enrollment.\(index)",
                title: school ?? "Enrollment",
                lines: enrollment.fields.map(enrollmentLine)
            ))
        }
        if !info.contactFields.isEmpty {
            sections.append(ProfileSection(
                id: "studentInfo.contact",
                title: "Contact",
                lines: info.contactFields.map(contactLine)
            ))
        }
        if !info.studentFields.isEmpty {
            sections.append(ProfileSection(
                id: "studentInfo.student",
                title: "Student details",
                lines: info.studentFields.map { Line(label: SourceFieldText.label($0.label), value: $0.value) }
            ))
        }
        return sections
    }

    /// Skyward's "Call" is the student's own phone number.
    private static func contactLine(_ field: StudentInfoField) -> Line {
        let label = SourceFieldText.label(field.label)
        return Line(label: SourceFieldText.key(label) == "call" ? "Phone" : label, value: field.value)
    }

    /// An enrollment's "Phone" is the school's, so it is named apart from
    /// the student's own. Staff names are set as people's names.
    private static func enrollmentLine(_ field: StudentInfoField) -> Line {
        let label = SourceFieldText.label(field.label)
        switch SourceFieldText.key(label) {
        case "phone":
            return Line(label: "School phone", value: field.value)
        case "principal", "counselor", "disciplineofficer":
            let name = SourceFieldText.value(field.value).map(PersonName.display) ?? field.value
            return Line(label: label, value: name)
        default:
            return Line(label: label, value: field.value)
        }
    }
}

/// The photo and the student's name, side by side, or the photo above the
/// name at accessibility sizes. A photo that couldn't load leaves a quiet
/// placeholder and a short note; the rest of the page is unaffected.
private struct StudentHeader: View {
    var info: StudentInfoData
    var photoWidth: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let image = info.photoData.flatMap(UIImage.init(data:))
        let photoFailed = image == nil && (info.photoLoadFailed || info.photoData != nil)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    StudentPhoto(image: image, width: photoWidth)
                    nameBlock(photoFailed: photoFailed)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    StudentPhoto(image: image, width: photoWidth)
                    nameBlock(photoFailed: photoFailed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nameBlock(photoFailed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PersonName.display(info.name))
                .font(.title2.bold())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("studentInfo.name")
            if photoFailed {
                Text("Photo couldn't be loaded")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("studentInfo.photoUnavailable")
            }
        }
    }
}

/// The school photo, scaled to fit a portrait frame so nothing is cropped,
/// or a quiet person placeholder in the same frame.
private struct StudentPhoto: View {
    var image: UIImage?
    var width: CGFloat

    private var height: CGFloat { width * 4 / 3 }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
    }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(shape)
                .frame(maxWidth: width, maxHeight: height)
                .accessibilityLabel("Student photo")
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("studentInfo.photo")
        } else {
            shape
                .fill(Color.well)
                .frame(width: width, height: height)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: width * 0.42))
                        .foregroundStyle(Color.faint)
                }
                .accessibilityHidden(true)
        }
    }
}
