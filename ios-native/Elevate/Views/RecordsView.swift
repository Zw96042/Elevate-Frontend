import SwiftUI

/// School records in one place: past courses, documents, student info and
/// fees. This page stores and fetches nothing; each page beneath loads its
/// own data when opened.
struct RecordsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingSettings = false
    @State private var showingConnect = false

    fileprivate struct Destination: Identifiable {
        var route: RecordsRoute
        var symbol: String
        var title: String
        var note: String
        var identifier: String
        var id: String { identifier }
    }

    /// Titles match the screens they open.
    private let destinations: [Destination] = [
        Destination(route: .pastCourses, symbol: "books.vertical", title: "Past courses",
                    note: "Grades from earlier years", identifier: "records.pastCourses"),
        Destination(route: .documents, symbol: "doc.text", title: "Documents",
                    note: "Report cards and files", identifier: "records.documents"),
        Destination(route: .studentInfo, symbol: "person.text.rectangle", title: "Student Info",
                    note: "Enrollment and contacts", identifier: "records.studentInfo"),
        Destination(route: .fees, symbol: "creditcard", title: "Fees",
                    note: "Charges and payments", identifier: "records.fees"),
    ]

    var body: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.recordsPath) {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to see past courses, documents, student info, and fees from your school.") {
                        showingConnect = true
                    }
                } else {
                    destinationGrid
                }
            }
            .screenTitle("Records") { showingSettings = true }
            .background(Color.appBackground.ignoresSafeArea())
            .accessibilityIdentifier("records.screen")
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
            .navigationDestination(for: RecordsRoute.self) { route in
                // The root hides the bar for its own header; pushed screens
                // keep their inline titles and Back.
                Group {
                    switch route {
                    case .pastCourses:
                        PastCoursesView()
                    case .pastCourse(let course):
                        HistoricalCourseDetailView(course: course)
                    case .documents:
                        DocumentsView()
                    case .studentInfo:
                        StudentInfoView()
                    case .fees:
                        FeesView()
                    }
                }
                .toolbar(.visible, for: .navigationBar)
            }
        }
    }

    /// The four pages as an open two-by-two grid on the page: a hairline
    /// between the columns and one between the rows, with no surfaces. Cells
    /// in a row share a height. At accessibility sizes the cells stack in one
    /// column divided by inset hairlines.
    private var destinationGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize {
                    ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                        if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                        cell(destination)
                    }
                } else {
                    ForEach(Array(stride(from: 0, to: destinations.count, by: 2)), id: \.self) { start in
                        if start > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                        HStack(spacing: 0) {
                            cell(destinations[start])
                            if start + 1 < destinations.count {
                                ColumnRule()
                                cell(destinations[start + 1])
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .softScrollEdges()
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The whole cell is the link; it takes the row pressed fill only while
    /// touched.
    private func cell(_ destination: Destination) -> some View {
        NavigationLink(value: destination.route) {
            RecordCell(destination: destination)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier(destination.identifier)
    }
}

/// One page as an open grid cell: its symbol in the action color, the page
/// name, and a short muted line naming what it holds. Text starts at the page
/// margin and wraps rather than truncating.
private struct RecordCell: View {
    var destination: RecordsView.Destination
    @ScaledMetric(relativeTo: .title2) private var symbolHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: destination.symbol)
                .font(.title2)
                .foregroundStyle(Color.themeAccent)
                .frame(height: symbolHeight, alignment: .leading)
                .accessibilityHidden(true)
            Text(destination.title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .padding(.top, 12)
            Text(destination.note)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The hairline between the grid's columns, the height of its row.
private struct ColumnRule: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.rule)
            .frame(width: 1 / max(1, displayScale))
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
