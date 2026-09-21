import Foundation
import Observation
import CapKit

/// A signed-in identity on one Cap server. Several can coexist (cap.so plus
/// a self-hosted instance); one is active at a time.
struct Account: Codable, Identifiable, Hashable {
    var id: UUID
    var server: CapServer
    var apiKey: String
    var userId: String
    var email: String
    var displayName: String
    var addedAt: Date

    var label: String { displayName.isEmpty ? email : displayName }
}

@MainActor
@Observable
final class SessionStore {
    private(set) var accounts: [Account] = []
    private(set) var activeAccountId: UUID?
    private(set) var client: CapClient?
    var bootstrap: Bootstrap?
    /// Set when the server answered 401 for the active account: the key was
    /// revoked (e.g. the same user signed in on another phone). The UI shows
    /// a re-authentication prompt instead of silently dropping the account.
    var needsReauth = false
    var lastError: String?

    private static let accountsKey = "accounts.v1"
    private static let activeKey = "activeAccountId.v1"

    var activeAccount: Account? {
        accounts.first { $0.id == activeAccountId }
    }

    var isSignedIn: Bool { activeAccount != nil }

    init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Keychain.read(Self.accountsKey),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: Self.activeKey), let id = UUID(uuidString: raw),
           accounts.contains(where: { $0.id == id }) {
            activeAccountId = id
        } else {
            activeAccountId = accounts.first?.id
        }
        rebuildClient()
    }

    private func persist() {
        do {
            try Keychain.write(Self.accountsKey, JSONEncoder().encode(accounts))
        } catch {
            lastError = "Could not save accounts to the Keychain: \(error)"
        }
        if let activeAccountId {
            UserDefaults.standard.set(activeAccountId.uuidString, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }

    private func rebuildClient() {
        needsReauth = false
        bootstrap = nil
        if let account = activeAccount {
            client = CapClient(server: account.server, apiKey: account.apiKey)
        } else {
            client = nil
        }
    }

    // MARK: Account lifecycle

    /// Finishes a sign-in: fetches the profile so the account has a name, then
    /// stores it and makes it active. Throws if the key does not work.
    func completeSignIn(server: CapServer, apiKey: String) async throws {
        let client = CapClient(server: server, apiKey: apiKey)
        let boot = try await client.bootstrap()
        let account = Account(
            id: UUID(), server: server, apiKey: apiKey,
            userId: boot.user.id, email: boot.user.email,
            displayName: boot.user.displayName, addedAt: Date()
        )
        // Same user on the same server: replace rather than duplicate.
        accounts.removeAll { $0.server == server && $0.userId == boot.user.id }
        accounts.append(account)
        activeAccountId = account.id
        persist()
        self.client = client
        self.bootstrap = boot
        needsReauth = false
    }

    func switchTo(_ account: Account) {
        guard accounts.contains(where: { $0.id == account.id }) else { return }
        activeAccountId = account.id
        persist()
        rebuildClient()
    }

    /// Revokes the key on the server (best effort) and forgets the account.
    func signOut(_ account: Account) async {
        if accounts.contains(where: { $0.id == account.id }) {
            try? await CapClient(server: account.server, apiKey: account.apiKey).revokeSession()
        }
        accounts.removeAll { $0.id == account.id }
        if activeAccountId == account.id {
            activeAccountId = accounts.first?.id
        }
        persist()
        rebuildClient()
    }

    /// Replaces the key of an account whose old key was revoked.
    func refreshKey(for account: Account, apiKey: String) async throws {
        try await completeSignIn(server: account.server, apiKey: apiKey)
    }

    func loadBootstrap() async {
        guard let client else { return }
        do {
            bootstrap = try await client.bootstrap()
        } catch let error as CapError where error.isAuthFailure {
            needsReauth = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setActiveOrganization(_ id: String) async {
        guard let client else { return }
        do {
            bootstrap = try await client.setActiveOrganization(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Call from any view that gets a `CapError` back so a 401 turns into the
    /// re-auth prompt everywhere, not just on launch.
    func handle(_ error: Error) {
        if let capError = error as? CapError, capError.isAuthFailure {
            needsReauth = true
        }
    }
}
