import SwiftUI
import UIKit
import CapKit

struct CapDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let library: LibraryModel

    @State private var cap: CapSummary
    @State private var detail: CapDetail?
    @State private var player = PlayerModel()
    @State private var error: String?
    @State private var commentText = ""
    @State private var sendingComment = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showPassword = false
    @State private var passwordText = ""
    @State private var showDeleteConfirm = false
    @State private var showAnalytics = false
    @State private var downloaded: DownloadedFile?
    @State private var downloading = false

    init(cap: CapSummary, library: LibraryModel) {
        _cap = State(initialValue: cap)
        self.library = library
    }

    private var isOwner: Bool {
        cap.ownedByCurrentUser ?? (cap.ownerId == session.activeAccount?.userId)
    }

    private var shareURL: URL? { URL(string: detail?.shareUrl ?? cap.shareUrl) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlayerView(model: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .padding(.horizontal, 16)

                titleBlock.padding(.horizontal, 16)
                actionRow.padding(.horizontal, 16)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.Colors.danger).padding(.horizontal, 16)
                }
                if let summary = detail?.summary, !summary.isEmpty {
                    section("Summary") {
                        Text(summary).font(.subheadline).foregroundStyle(Theme.Colors.ink)
                    }
                }
                if let chapters = detail?.chapters, !chapters.isEmpty {
                    section("Chapters") { chaptersList(chapters) }
                }
                section("Comments") { commentsBlock }
            }
            .padding(.vertical, 12)
        }
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { overflowMenu }
        }
        .task {
            guard let client = session.client else { return }
            async let playbackLoad: Void = player.load(capId: cap.id, client: client)
            await loadDetail(client: client)
            await playbackLoad
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let client = session.client {
                Task { await player.refreshIfStale(capId: cap.id, client: client) }
            }
        }
        .onDisappear { player.stop() }
        .alert("Rename", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert(cap.isProtected ? "Change password" : "Set a password", isPresented: $showPassword) {
            SecureField("Password", text: $passwordText)
            Button("Save") { Task { await setPassword(passwordText) } }
            if cap.isProtected {
                Button("Remove password", role: .destructive) { Task { await setPassword(nil) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Viewers of the share link will need this password.")
        }
        .confirmationDialog("Delete this cap?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteCap() } }
        } message: {
            Text("This removes the recording from the server for everyone. It can't be undone.")
        }
        .sheet(isPresented: $showAnalytics) {
            AnalyticsSheet(capId: cap.id, title: cap.title)
        }
        .sheet(item: $downloaded) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: Pieces

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cap.title.isEmpty ? "Untitled" : cap.title)
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.Colors.ink)
            HStack(spacing: 8) {
                Text(cap.ownerName.isEmpty ? "Unknown" : cap.ownerName)
                Text("·")
                Text(Format.absolute(cap.createdDate))
            }
            .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            HStack(spacing: 8) {
                Pill(text: Format.count(cap.viewCount, "view"), systemImage: "eye")
                Pill(text: Format.duration(cap.durationSeconds), systemImage: "clock")
                if cap.isProtected {
                    Pill(text: "Password", systemImage: "lock.fill", tint: Theme.Colors.warning)
                } else if cap.isPublic {
                    Pill(text: "Anyone with link", systemImage: "link", tint: Theme.Colors.success)
                } else {
                    Pill(text: "Private", systemImage: "eye.slash")
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let shareURL {
                ShareLink(item: shareURL, subject: Text(cap.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BrandButtonStyle())
            }
            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { r in
                    Button {
                        player.rate = Float(r)
                    } label: {
                        if player.rate == Float(r) { Label("\(r.formatted())×", systemImage: "checkmark") } else { Text("\(r.formatted())×") }
                    }
                }
            } label: {
                Text("\(Double(player.rate).formatted())×")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .frame(width: 72)
                    .padding(.vertical, 14)
                    .foregroundStyle(Theme.Colors.brand)
                    .background(Theme.Colors.brandSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
        }
    }

    private var overflowMenu: some View {
        Menu {
            if let shareURL {
                Button {
                    UIPasteboard.general.url = shareURL
                } label: { Label("Copy link", systemImage: "link") }
                Link(destination: shareURL) { Label("Open in browser", systemImage: "safari") }
            }
            if isOwner {
                Divider()
                Button { renameText = cap.title; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                Button { Task { await toggleVisibility() } } label: {
                    Label(cap.isPublic ? "Make private" : "Make public", systemImage: cap.isPublic ? "eye.slash" : "eye")
                }
                Button { passwordText = ""; showPassword = true } label: {
                    Label(cap.isProtected ? "Change password…" : "Set password…", systemImage: "lock")
                }
                Button { showAnalytics = true } label: { Label("Analytics", systemImage: "chart.bar") }
                Button { Task { await download() } } label: {
                    Label(downloading ? "Downloading…" : "Download video", systemImage: "arrow.down.circle")
                }
                .disabled(downloading)
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.Colors.ink)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, 16)
    }

    private func chaptersList(_ chapters: [CapChapter]) -> some View {
        VStack(spacing: 0) {
            ForEach(chapters) { chapter in
                Button { player.seek(to: chapter.start) } label: {
                    HStack {
                        Text(Format.duration(chapter.start))
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.Colors.brand)
                            .frame(width: 52, alignment: .leading)
                        Text(chapter.title).font(.subheadline).foregroundStyle(Theme.Colors.ink)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                Divider()
            }
        }
    }

    @ViewBuilder
    private var commentsBlock: some View {
        let comments = detail?.comments ?? []
        let reactions = comments.filter { $0.type == .emoji }
        let texts = comments.filter { $0.type == .text }

        HStack(spacing: 8) {
            ForEach(["👍", "❤️", "🔥", "😂", "👀", "🎉"], id: \.self) { emoji in
                Button { Task { await react(emoji) } } label: {
                    Text(emoji).font(.title3)
                        .padding(6)
                        .background(Theme.Colors.filler, in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        if !reactions.isEmpty {
            Text(reactions.map(\.content).joined(separator: " "))
                .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
        }
        if texts.isEmpty {
            Text("No comments yet.").font(.footnote).foregroundStyle(Theme.Colors.inkFaint)
        } else {
            ForEach(texts) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(comment.author.name ?? "Someone").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Colors.ink)
                        if let t = comment.timestamp {
                            Button(Format.duration(t)) { player.seek(to: t) }
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.Colors.brand)
                        }
                        Spacer()
                        Text(Format.relative(comment.createdDate)).font(.caption2).foregroundStyle(Theme.Colors.inkFaint)
                        if comment.author.id == session.activeAccount?.userId {
                            Button(role: .destructive) { Task { await deleteComment(comment) } } label: {
                                Image(systemName: "trash").font(.caption2)
                            }
                        }
                    }
                    Text(comment.content).font(.subheadline).foregroundStyle(Theme.Colors.ink)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        HStack(spacing: 8) {
            TextField("Comment at \(Format.duration(player.currentSeconds))", text: $commentText, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(Theme.Colors.filler, in: RoundedRectangle(cornerRadius: 10))
            Button { Task { await sendComment() } } label: {
                if sendingComment { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
            }
            .disabled(sendingComment || commentText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Data

    private func loadDetail(client: CapClient) async {
        do {
            let d = try await client.cap(id: cap.id)
            detail = d
            cap = d.cap
        } catch {
            self.error = error.localizedDescription
            session.handle(error)
        }
    }

    private func rename() async {
        guard let client = session.client else { return }
        let title = renameText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        await run { cap = try await client.updateTitle(id: cap.id, title: title); library.replace(cap) }
    }

    private func toggleVisibility() async {
        guard let client = session.client else { return }
        await run { cap = try await client.updateSharing(id: cap.id, isPublic: !cap.isPublic); library.replace(cap) }
    }

    private func setPassword(_ password: String?) async {
        guard let client = session.client else { return }
        let value = password?.trimmingCharacters(in: .whitespaces)
        if let value, value.isEmpty { return }
        await run { cap = try await client.updatePassword(id: cap.id, password: value); library.replace(cap) }
    }

    private func deleteCap() async {
        guard let client = session.client else { return }
        await run {
            try await client.deleteCap(id: cap.id)
            library.remove(id: cap.id)
            dismiss()
        }
    }

    private func sendComment() async {
        guard let client = session.client else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendingComment = true
        defer { sendingComment = false }
        await run {
            let created = try await client.createComment(capId: cap.id, content: text, timestamp: player.currentSeconds)
            detail?.comments.append(created)
            cap.commentCount += 1
            commentText = ""
        }
    }

    private func react(_ emoji: String) async {
        guard let client = session.client else { return }
        await run {
            let created = try await client.createReaction(capId: cap.id, emoji: emoji, timestamp: player.currentSeconds)
            detail?.comments.append(created)
            cap.reactionCount += 1
        }
    }

    private func deleteComment(_ comment: CapComment) async {
        guard let client = session.client else { return }
        await run {
            try await client.deleteComment(id: comment.id)
            detail?.comments.removeAll { $0.id == comment.id }
            if comment.type == .text { cap.commentCount = max(0, cap.commentCount - 1) } else { cap.reactionCount = max(0, cap.reactionCount - 1) }
        }
    }

    private func download() async {
        guard let client = session.client else { return }
        downloading = true
        defer { downloading = false }
        await run {
            let info = try await client.download(id: cap.id)
            guard let remote = URL(string: info.url) else { throw CapError.invalidResponse }
            let (temp, _) = try await URLSession.shared.download(from: remote)
            let safeName = info.fileName.isEmpty ? "\(cap.id).mp4" : info.fileName
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
            downloaded = DownloadedFile(url: dest)
        }
    }

    private func run(_ work: () async throws -> Void) async {
        error = nil
        do { try await work() } catch {
            self.error = error.localizedDescription
            session.handle(error)
        }
    }
}

struct DownloadedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AnalyticsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let capId: String
    let title: String
    @State private var range: AnalyticsRange = .week
    @State private var response: AnalyticsResponse?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Picker("Range", selection: $range) {
                    Text("24h").tag(AnalyticsRange.day)
                    Text("7 days").tag(AnalyticsRange.week)
                    Text("30 days").tag(AnalyticsRange.month)
                    Text("All time").tag(AnalyticsRange.lifetime)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if let error {
                    Text(error).foregroundStyle(Theme.Colors.danger)
                } else if let response {
                    if !response.available || response.data == nil {
                        Text("Analytics aren't available on this server.").foregroundStyle(Theme.Colors.inkSoft)
                    } else if let data = response.data {
                        Section("Totals") {
                            LabeledContent("Views", value: data.counts.views.formatted())
                            LabeledContent("Comments", value: data.counts.comments.formatted())
                            LabeledContent("Reactions", value: data.counts.reactions.formatted())
                        }
                        breakdown("Countries", data.breakdowns.countries)
                        breakdown("Browsers", data.breakdowns.browsers)
                        breakdown("Devices", data.breakdowns.devices)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: range) { await load() }
        }
    }

    @ViewBuilder
    private func breakdown(_ title: String, _ rows: [AnalyticsBreakdown]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows.prefix(8), id: \.name) { row in
                    LabeledContent(row.name, value: "\(row.views.formatted()) · \(Int(row.percentage.rounded()))%")
                }
            }
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        error = nil
        do { response = try await client.analytics(id: capId, range: range) } catch { self.error = error.localizedDescription }
    }
}
