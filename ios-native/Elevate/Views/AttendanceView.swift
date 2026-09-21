import SwiftUI

/// Source attendance records grouped by school date, newest first. Each row
/// shows Skyward's own description; nothing is counted or categorized.
struct AttendanceView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingConnect = false

    /// Changes whenever the refresh loop should start over or stop: another
    /// account, sign-in state, this tab leaving view, or the app backgrounding.
    private struct RefreshLoopIdentity: Hashable {
        var accountRevision: Int
        var canShowData: Bool
        var isSelected: Bool
        var isActive: Bool
    }

    private var refreshLoopIdentity: RefreshLoopIdentity {
        RefreshLoopIdentity(
            accountRevision: store.accountRevision,
            canShowData: store.canShowData,
            isSelected: router.selectedTab == .calendar,
            isActive: scenePhase == .active
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to see attendance records from your school.") {
                        showingConnect = true
                    }
                } else if store.attendance == nil, let error = store.attendanceError {
                    ErrorStateView(title: "Couldn't load attendance", message: error) {
                        await store.refreshAttendance(force: true)
                    }
                } else {
                    attendanceList
                }
            }
            .screenTitle("Attendance") { showingSettings = true }
            .background(Color.appBackground.ignoresSafeArea())
            .accessibilityIdentifier("attendance.screen")
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
            .task(id: refreshLoopIdentity) {
                let identity = refreshLoopIdentity
                guard identity.isSelected, identity.isActive, identity.canShowData else { return }
                // The store owns the first fetch and later due refreshes; a
                // new identity cancels this loop.
                await store.runAttendanceRefreshLoop()
            }
        }
    }

    private var statusStrip: some View {
        StatusStrip(
            lastUpdated: store.attendanceLastUpdated,
            isRefreshing: store.attendanceLoading,
            error: store.attendance == nil ? nil : store.attendanceError
        ) {
            await store.refreshAttendance(force: true)
        }
        .padding(.horizontal, Metrics.page)
    }

    private var attendanceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip

                if let attendance = store.attendance {
                    if attendance.availability == .unavailable {
                        EmptyStateView(
                            title: "Attendance isn't available",
                            message: "Skyward hasn't made attendance available for this account."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("attendance.unavailable")
                    } else if attendance.records.isEmpty {
                        EmptyStateView(
                            title: "No attendance records",
                            message: "Skyward has no attendance records to show."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("attendance.empty")
                    } else {
                        recordGroups(AttendanceDay.days(from: attendance.records))
                    }
                } else {
                    // Nothing fetched or saved yet, including before the
                    // first request starts.
                    loadingRows
                }
            }
            .padding(.bottom, 24)
        }
        .visibleRefreshable {
            await store.refreshAttendance(force: true)
        }
    }

