import SwiftUI
import AVKit
import Observation
import CapKit

/// Owns the AVPlayer for one cap. Playback URLs are pre-signed and expire
/// after an hour, so the model remembers when it fetched one and re-fetches
/// (preserving position) when the app comes back after a long pause or the
/// player reports a failure.
@MainActor
@Observable
final class PlayerModel {
    let player = AVPlayer()
    private(set) var playback: Playback?
    private(set) var fetchedAt: Date?
    var error: String?
    var isLoading = false
    var rate: Float = 1.0 {
        didSet {
            player.defaultRate = rate
            if player.timeControlStatus == .playing { player.rate = rate }
        }
    }
    var currentSeconds: Double = 0
    /// True when the server handed back its own playlist URL (see `load`).
    var stillFinalizing = false

    // Written once in init and read in deinit, which is nonisolated; nothing
    // else touches them, so the unsafe opt-out is sound. ObservationIgnored keeps
    // them plain stored properties so the isolation attribute applies.
    @ObservationIgnored nonisolated(unsafe) private var timeObserver: Any?
    @ObservationIgnored nonisolated(unsafe) private var failureObserver: NSObjectProtocol?
    private static let refreshAfter: TimeInterval = 50 * 60

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.currentSeconds = time.seconds.isFinite ? time.seconds : 0 }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.error = "Playback stopped. Pull to reload if it keeps happening." }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }

    func load(capId: String, client: CapClient, resumeAt: Double? = nil, autoplay: Bool = true) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let playback = try await client.playback(id: capId)
            guard let url = URL(string: playback.url) else { throw CapError.invalidResponse }
            // A playlist served by the Cap server itself means the desktop
            // recording is still being finalized; the server only accepts a
            // browser cookie there, so a bearer client can't stream it yet
            // unless the cap is public. Say so instead of failing silently.
            let serverHost = await client.server.host.lowercased()
            if playback.kind == .hls, url.host?.lowercased() == serverHost {
                stillFinalizing = true
            } else {
                stillFinalizing = false
            }
            var options: [String: Any] = [:]
            let headers = await client.playerHeaders(for: url)
            if !headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = headers }
            let asset = AVURLAsset(url: url, options: options)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 8
            player.replaceCurrentItem(with: item)
            self.playback = playback
            self.fetchedAt = Date()
            if let resumeAt, resumeAt > 0 {
                await player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
            }
            player.defaultRate = rate
            if autoplay { player.play() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-fetch the signed URL if it is close to expiring.
    func refreshIfStale(capId: String, client: CapClient) async {
        guard let fetchedAt, Date().timeIntervalSince(fetchedAt) > Self.refreshAfter else { return }
        let wasPlaying = player.timeControlStatus == .playing
        await load(capId: capId, client: client, resumeAt: currentSeconds, autoplay: wasPlaying)
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if player.timeControlStatus != .playing { player.play() }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct PlayerView: View {
    let model: PlayerModel

    var body: some View {
        ZStack {
            VideoPlayer(player: model.player)
            if model.isLoading {
                ProgressView().tint(.white)
            }
            if model.stillFinalizing && model.error == nil && !model.isLoading {
                Text("Still finalizing on the server. Try again in a minute.")
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
                    .padding(8).background(.black.opacity(0.6), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
            }
            if let error = model.error, !model.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.title2)
                    Text(error).font(.footnote).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .padding()
            }
        }
        .background(Color.black)
    }
}
