import SwiftUI
import Observation
import CapKit

/// What the list is showing: the user's own caps, or one space/organization.
enum LibraryScope: Hashable, Identifiable {
    case mine
    case space(id: String, name: String)

    var id: String {
        switch self {
        case .mine: return "mine"
        case .space(let id, _): return "space:\(id)"
        }
    }

    var title: String {
        switch self {
        case .mine: return "My Caps"
        case .space(_, let name): return name
        }
    }

    var spaceId: String? {
        if case .space(let id, _) = self { return id }
        return nil
    }
}

@MainActor
@Observable
final class LibraryModel {
    var scope: LibraryScope = .mine
    var folderPath: [CapFolder] = []
    var folders: [CapFolder] = []
    var caps: [CapSummary] = []
    var total = 0
    var hasMore = false
    var isLoading = false
    var error: String?
    var searchText = ""

    private var page = 1
    private let pageSize = 30

    var currentFolder: CapFolder? { folderPath.last }

    var visibleCaps: [CapSummary] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return caps }
        return caps.filter { $0.title.lowercased().contains(q) || $0.ownerName.lowercased().contains(q) }
    }

    func reload(using client: CapClient) async {
        page = 1
        await fetch(using: client, append: false)
    }

    func loadMoreIfNeeded(current cap: CapSummary, using client: CapClient) async {
        guard hasMore, !isLoading, searchText.isEmpty else { return }
        guard let index = caps.firstIndex(of: cap), index >= caps.count - 6 else { return }
        page += 1
        await fetch(using: client, append: true)
    }

    private func fetch(using client: CapClient, append: Bool) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await client.listCaps(folderId: currentFolder?.id, spaceId: scope.spaceId, page: page, limit: pageSize)
            if append {
                let known = Set(caps.map(\.id))
                caps.append(contentsOf: result.caps.filter { !known.contains($0.id) })
            } else {
                caps = result.caps
                folders = result.folders
            }
            total = result.total
            hasMore = result.hasMore
        } catch {
            self.error = error.localizedDescription
            onAuthFailure?(error)
        }
    }

    /// Routed to the session so a revoked key triggers the re-auth sheet.
    var onAuthFailure: (@MainActor (Error) -> Void)?

    func enter(_ folder: CapFolder) { folderPath.append(folder) }
    func popTo(_ folder: CapFolder?) {
        if let folder, let i = folderPath.firstIndex(of: folder) {
            folderPath = Array(folderPath[...i])
        } else {
            folderPath = []
        }
    }

    /// Apply a server-confirmed edit (rename, visibility) without a refetch.
    func replace(_ cap: CapSummary) {
        if let i = caps.firstIndex(where: { $0.id == cap.id }) { caps[i] = cap }
    }

    func remove(id: String) {
        caps.removeAll { $0.id == id }
        total = max(0, total - 1)
    }
}

struct LibraryView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = LibraryModel()

    private var scopes: [LibraryScope] {
        var out: [LibraryScope] = [.mine]
        for space in session.bootstrap?.spaces ?? [] {
            out.append(.space(id: space.id, name: space.name))
        }
        return out
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Colors.background)
                .navigationTitle(model.currentFolder?.name ?? model.scope.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.currentFolder != nil {
                            Button { model.popTo(model.folderPath.dropLast().last); reload() } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { scopeMenu }
                }
                .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search titles")
                .refreshable { await refresh() }
                .navigationDestination(for: CapSummary.self) { cap in
                    CapDetailView(cap: cap, library: model)
                }
        }
        .task(id: session.activeAccountId) {
            model.onAuthFailure = { session.handle($0) }
            model.scope = .mine
            model.popTo(nil)
            if session.bootstrap == nil { await session.loadBootstrap() }
            await refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.caps.isEmpty && model.folders.isEmpty {
            if model.isLoading {
                ProgressView("Loading your caps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
                ContentUnavailableView {
                    Label("Couldn't load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { reload() }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView("No caps here yet", systemImage: "rectangle.stack.badge.play",
                                       description: Text(emptyHint))
            }
        } else {
            list
        }
    }

    private var emptyHint: String {
        switch model.scope {
        case .mine: return "Recordings you make with Cap on your desktop show up here."
        case .space: return "Nothing has been shared to this space."
        }
    }

    private var list: some View {
        List {
            if !model.folders.isEmpty && model.searchText.isEmpty {
                Section {
                    ForEach(model.folders) { folder in
                        Button { model.enter(folder); reload() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill").foregroundStyle(folderTint(folder.color))
                                Text(folder.name).foregroundStyle(Theme.Colors.ink)
                                Spacer()
                                Text("\(folder.videoCount)").font(.caption).foregroundStyle(Theme.Colors.inkFaint)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.Colors.inkFaint)
                            }
                        }
                    }
                }
            }
            Section {
                ForEach(model.visibleCaps) { cap in
                    NavigationLink(value: cap) {
                        CapRow(cap: cap, client: session.client)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .task { if let client = session.client { await model.loadMoreIfNeeded(current: cap, using: client) } }
                }
                if model.isLoading && !model.caps.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                }
            } header: {
                if model.total > 0 && model.searchText.isEmpty {
                    Text(Format.count(model.total, "cap")).textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var scopeMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { model.scope }, set: { newScope in
                model.scope = newScope
                model.popTo(nil)
                reload()
            })) {
                ForEach(scopes) { scope in
                    Label(scope.title, systemImage: scope.spaceId == nil ? "person" : "person.2").tag(scope)
                }
            }
            if let orgs = session.bootstrap?.organizations, orgs.count > 1 {
                Divider()
                Picker("Organization", selection: Binding(
                    get: { session.bootstrap?.activeOrganizationId ?? "" },
                    set: { id in Task { await session.setActiveOrganization(id); model.scope = .mine; model.popTo(nil); reload() } }
                )) {
                    ForEach(orgs) { org in Text(org.name).tag(org.id) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private func folderTint(_ color: FolderColor) -> Color {
        switch color {
        case .normal: return Theme.Colors.inkSoft
        case .blue: return Theme.Colors.brand
        case .red: return Theme.Colors.danger
        case .yellow: return Theme.Colors.warning
        }
    }

    private func reload() { Task { await refresh() } }

    private func refresh() async {
        guard let client = session.client else { return }
        await model.reload(using: client)
    }
}

struct CapRow: View {
    let cap: CapSummary
    let client: CapClient?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                CapThumbnail(cap: cap, client: client)
                if cap.isReady {
                    Text(Format.duration(cap.durationSeconds))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(cap.title.isEmpty ? "Untitled" : cap.title)
                    .font(.headline).foregroundStyle(Theme.Colors.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Format.relative(cap.createdDate))
                    Text("·")
                    Label("\(cap.viewCount)", systemImage: "eye").labelStyle(.titleAndIcon)
                    if cap.commentCount > 0 {
                        Text("·")
                        Label("\(cap.commentCount)", systemImage: "bubble.left")
                    }
                    Spacer()
                    if cap.isProtected {
                        Image(systemName: "lock.fill")
                    } else if !cap.isPublic {
                        Image(systemName: "eye.slash")
                    }
                }
                .font(.caption).foregroundStyle(Theme.Colors.inkSoft)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .card()
    }
}
