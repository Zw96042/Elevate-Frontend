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

