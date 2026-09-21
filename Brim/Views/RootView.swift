import SwiftUI
import CapKit

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                MainTabs()
            } else {
                SignInView(mode: .fresh)
            }
        }
        .sheet(isPresented: Binding(get: { session.needsReauth && session.activeAccount != nil },
                                    set: { if !$0 { session.needsReauth = false } })) {
            if let account = session.activeAccount {
                SignInView(mode: .reauth(account))
                    .interactiveDismissDisabled()
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack.badge.play") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
