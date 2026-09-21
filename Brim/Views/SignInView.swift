import SwiftUI
import AuthenticationServices
import CapKit

/// Server → email → six-digit code, or a web sign-in for servers with
/// Google/Apple/SSO. Also used to refresh a revoked key (`.reauth`).
struct SignInView: View {
    enum Mode {
        case fresh
        case addAccount
        case reauth(Account)
    }

    let mode: Mode
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum Step { case server, email, code }
    private enum Host: String, CaseIterable { case cloud = "cap.so", selfHosted = "Self-hosted" }

    @State private var step: Step = .server
    @State private var hostChoice: Host = .selfHosted
    @State private var serverText = ""
    @State private var server: CapServer?
    @State private var authConfig: AuthConfig?
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var webAuth = WebAuthSession()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    switch step {
                    case .server: serverStep
                    case .email: emailStep
                    case .code: codeStep
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Theme.Colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(Theme.Colors.background)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: Steps

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BrimMark().frame(width: 40, height: 40)
                Text("Brim").font(.largeTitle.weight(.semibold)).foregroundStyle(Theme.Colors.ink)
            }
            Text(headerSubtitle).font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
        }
    }

    private var isReauth: Bool {
        if case .reauth = mode { return true }
        return false
    }

    /// `.fresh` is the root screen; `.addAccount` and `.reauth` are presented in a sheet.
    private var isModal: Bool {
        if case .fresh = mode { return false }
        return true
    }

    private var headerSubtitle: String {
        switch mode {
        case .fresh, .addAccount: return "Watch and share your Cap recordings from cap.so or your own server."
        case .reauth(let account): return "Your session on \(account.server.displayHost) expired. Sign in again to keep going."
        }
    }

    private var serverStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where are your recordings?").font(.headline).foregroundStyle(Theme.Colors.ink)
            Picker("Server", selection: $hostChoice) {
                ForEach(Host.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if hostChoice == .selfHosted {
                TextField("cap.example.com", text: $serverText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .card()
                Text("The address you open Cap at in a browser. Needs a Cap server from mid-2026 or newer (it must have the mobile API).")
                    .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            }
            Button {
                Task { await chooseServer() }
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Continue") }
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(busy || (hostChoice == .selfHosted && serverText.trimmingCharacters(in: .whitespaces).isEmpty))

            if !isReauth {
                VStack(spacing: 4) {
                    Button("Try the demo") {
                        session.startDemo()
                        if isModal { dismiss() }
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("Explore Brim with sample recordings. Nothing leaves your phone.")
                        .font(.caption).foregroundStyle(Theme.Colors.inkFaint)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            serverBadge
            Text("Sign in with email").font(.headline).foregroundStyle(Theme.Colors.ink)
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .card()
            Text("We'll email you a six-digit code. New accounts are created only if the server allows sign-ups for your domain.")
                .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            Button {
                Task { await sendCode() }
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Send code") }
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(busy || !email.contains("@"))

            browserButtons
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            serverBadge
            Text("Enter the code").font(.headline).foregroundStyle(Theme.Colors.ink)
            Text("Sent to \(email).").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            TextField("123456", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .padding(12)
                .card()
            Button {
                Task { await verify() }
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Sign in") }
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(busy || code.trimmingCharacters(in: .whitespaces).count < 4)
            Button("Use a different email") { step = .email; code = ""; error = nil }
                .font(.footnote)
        }
    }

    private var serverBadge: some View {
        HStack {
            Pill(text: server?.displayHost ?? "", systemImage: "server.rack")
            Spacer()
            if !isReauth {
                Button("Change") { step = .server; error = nil }.font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var browserButtons: some View {
        let providers = authConfig?.availableProviders ?? []
        VStack(spacing: 10) {
            HStack {
                Rectangle().fill(Theme.Colors.cardBorder).frame(height: 1)
                Text("or").font(.caption).foregroundStyle(Theme.Colors.inkFaint)
                Rectangle().fill(Theme.Colors.cardBorder).frame(height: 1)
            }
            ForEach(providers, id: \.self) { provider in
                Button {
                    Task { await signInWithBrowser(provider: provider) }
                } label: {
                    Label(providerLabel(provider), systemImage: providerIcon(provider))
                }
                .buttonStyle(BrandButtonStyle(prominent: false))
            }
            Button {
                Task { await signInWithBrowser(provider: nil) }
            } label: {
                Label("Sign in in the browser", systemImage: "safari")
            }
            .buttonStyle(BrandButtonStyle(prominent: false))
            Text("Opens the server's own login page and hands the session back to Brim.")
                .font(.caption2).foregroundStyle(Theme.Colors.inkFaint)
        }
        .disabled(busy)
    }

    private func providerLabel(_ p: AuthProvider) -> String {
        switch p {
        case .google: return "Continue with Google"
        case .apple: return "Continue with Apple"
        case .workos: return "Continue with SSO"
        }
    }

    private func providerIcon(_ p: AuthProvider) -> String {
        switch p {
        case .google: return "g.circle"
        case .apple: return "apple.logo"
        case .workos: return "building.2"
        }
    }

    // MARK: Actions

    private func prefill() {
        if case .reauth(let account) = mode {
            server = account.server
            serverText = account.server.displayHost
            hostChoice = account.server.isCloud ? .cloud : .selfHosted
            email = account.email
            step = .email
            Task { authConfig = try? await CapClient(server: account.server).authConfig() }
        }
    }

    private func chooseServer() async {
        error = nil
        let candidate: CapServer?
        switch hostChoice {
        case .cloud: candidate = .cloud
        case .selfHosted: candidate = CapServer(userInput: serverText)
        }
        guard let candidate else {
            error = "That doesn't look like a web address."
            return
        }
        busy = true
        defer { busy = false }
        do {
            authConfig = try await CapClient(server: candidate).authConfig()
            server = candidate
            step = .email
        } catch CapError.notFound {
            error = "\(candidate.displayHost) answered, but it doesn't have Cap's mobile API. Update the server to a mid-2026 or newer build."
        } catch {
            self.error = "Could not reach \(candidate.displayHost): \(error.localizedDescription)"
        }
    }

    private func sendCode() async {
        guard let server else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await CapClient(server: server).requestEmailCode(email: email.trimmingCharacters(in: .whitespaces))
            step = .code
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        guard let server else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let client = CapClient(server: server)
            let key = try await client.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces), code: code.trimmingCharacters(in: .whitespaces))
            try await finish(server: server, apiKey: key.apiKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func signInWithBrowser(provider: AuthProvider?) async {
        guard let server else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let callback = try await webAuth.run(url: server.browserSignInURL(provider: provider))
            guard let parsed = CapServer.parseAuthCallback(callback) else {
                error = "The server sent back an unexpected response."
                return
            }
            try await finish(server: server, apiKey: parsed.apiKey)
        } catch let authError as ASWebAuthenticationSessionError where authError.code == .canceledLogin {
            // User closed the sheet; nothing to report.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func finish(server: CapServer, apiKey: String) async throws {
        try await session.completeSignIn(server: server, apiKey: apiKey)
        session.needsReauth = false
        if isModal { dismiss() }
    }
}

/// Runs the server's web login inside an in-app browser sheet and captures
/// the `cap://auth?api_key=…` redirect. The redirect is intercepted by the
/// session itself, so it never reaches another app that owns the `cap` scheme.
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var current: ASWebAuthenticationSession?

    func run(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "cap") { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? CapError.invalidResponse) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            current = session
            if !session.start() {
                continuation.resume(throwing: CapError.network("Could not open the sign-in page."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

/// Brim's own mark: a rounded blue tile with a white brim arc. Drawn in code
/// so the sign-in screen and About page never depend on the asset catalog.
struct BrimMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2EB4FF), Color(hex: 0x005CB1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                // Dome: the top half of a circle (trim 0.5→1 runs 9 o'clock → 3 o'clock over the top).
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .fill(.white)
                    .frame(width: s * 0.54, height: s * 0.54)
                    .offset(y: s * 0.08)
                // Brim: a wide bar under the dome. Dome + brim are centered on the tile.
                Capsule()
                    .fill(.white)
                    .frame(width: s * 0.72, height: s * 0.115)
                    .offset(y: s * 0.135)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
