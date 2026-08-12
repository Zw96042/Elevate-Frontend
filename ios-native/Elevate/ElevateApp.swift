import SwiftUI

@main
struct ElevateApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
        }
    }
}

struct RootTabView: View {
    private enum AppTab: Hashable {
        case courses
        case gpa
        case inbox
    }

    @Environment(AppStore.self) private var store
    @State private var theme = ThemeManager.shared
    @State private var selectedTab: AppTab = .courses

    var body: some View {
        TabView(selection: $selectedTab) {
            CoursesView()
                .tabItem { Label("Courses", systemImage: "graduationcap") }
                .tag(AppTab.courses)
            GPAView()
                .tabItem { Label("GPA", systemImage: "text.document") }
                .tag(AppTab.gpa)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "envelope") }
                .tag(AppTab.inbox)
        }
        .tint(Color.themeAccent)
        .preferredColorScheme(theme.appearance.colorScheme)
        .background(Color.appBackground.ignoresSafeArea())
        .onOpenURL { url in
            guard url.scheme == "com.zacharywilson.elevate" else { return }
            switch url.host {
            case "gpa": selectedTab = .gpa
            case "inbox": selectedTab = .inbox
            default: selectedTab = .courses
            }
        }
        .task {
            if store.canShowData {
                async let courses: Void = store.refreshCourses()
                async let messages: Void = store.refreshMessages()
                _ = await (courses, messages)
            }
        }
    }
}
