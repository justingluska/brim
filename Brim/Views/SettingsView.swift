import SwiftUI
import CapKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var showAddAccount = false
    @State private var accountToSignOut: Account?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Accounts") {
                    ForEach(session.accounts) { account in
                        Button {
                            if account.id != session.activeAccountId { session.switchTo(account) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: account.server.isCloud ? "cloud" : "server.rack")
                                    .foregroundStyle(Theme.Colors.brand).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.label).foregroundStyle(Theme.Colors.ink)
                                    Text("\(account.email) · \(account.server.displayHost)")
                                        .font(.caption).foregroundStyle(Theme.Colors.inkSoft)
                                }
                                Spacer()
                                if account.id == session.activeAccountId {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brand)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { accountToSignOut = account } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                        }
                    }
                    Button { showAddAccount = true } label: { Label("Add account", systemImage: "plus") }
                }

                if let boot = session.bootstrap {
                    Section("Signed in as") {
                        LabeledContent("Name", value: boot.user.displayName)
                        LabeledContent("Email", value: boot.user.email)
                        if let org = boot.organizations.first(where: { $0.id == boot.activeOrganizationId }) {
                            LabeledContent("Organization", value: org.name)
                        }
                    }
                }

                Section("About") {
                    HStack(spacing: 12) {
                        BrimMark().frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Brim").font(.headline)
                            Text("Version \(version)").font(.caption).foregroundStyle(Theme.Colors.inkSoft)
                        }
                    }
                    Text("Brim is an unofficial, open-source viewer for Cap recordings. It is not affiliated with, endorsed by, or sponsored by Cap Software, Inc. \"Cap\" is a trademark of Cap Software, Inc.")
                        .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    Link(destination: URL(string: "https://x.com/GLUSKA")!) {
                        HStack {
                            Label("Made by Justin Gluska", systemImage: "person")
                            Spacer()
                            Text("@GLUSKA").foregroundStyle(Theme.Colors.inkSoft)
                        }
                    }
                    Link(destination: URL(string: "https://github.com/justingluska/brim")!) {
                        Label("Source code and issues", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://cap.so")!) {
                        Label("Cap (cap.so)", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/justingluska/brim/blob/main/docs/privacy.md")!) {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }

                if let err = session.lastError {
                    Section("Last error") { Text(err).font(.footnote).foregroundStyle(Theme.Colors.danger) }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showAddAccount) {
            SignInView(mode: .addAccount)
        }
        .confirmationDialog("Sign out of \(accountToSignOut?.server.displayHost ?? "")?", isPresented: Binding(get: { accountToSignOut != nil }, set: { if !$0 { accountToSignOut = nil } }), titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                if let account = accountToSignOut { Task { await session.signOut(account) } }
                accountToSignOut = nil
            }
        } message: {
            Text("This revokes Brim's key on the server and removes the account from this phone.")
        }
    }
}
