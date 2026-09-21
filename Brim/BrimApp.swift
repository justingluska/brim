import SwiftUI
import AVFoundation

@main
struct BrimApp: App {
    @State private var session = SessionStore()

    init() {
        // Play recordings with the ring/silent switch on and keep audio going
        // in Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.Colors.brand)
        }
    }
}
