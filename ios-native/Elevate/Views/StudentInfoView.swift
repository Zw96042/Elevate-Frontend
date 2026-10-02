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

