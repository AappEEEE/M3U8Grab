import SwiftUI
import AVKit
import AVFoundation

/// 播放器：直接用 AVPlayer 播 m3u8 / 本地文件，必要时带上 Referer 头
struct PlayerSheet: View {
    let title: String
    let url: URL
    let referer: String?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failedText: String?
    @State private var failureObserver: NSObjectProtocol?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(.container, edges: .bottom)
                } else if let failedText {
                    VStack(spacing: 12) {
                        Image(systemName: "play.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.7))
                        Text(failedText)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: setup)
            .onDisappear(perform: teardown)
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    private func setup() {
        guard player == nil else { return }

        var options: [String: Any] = [:]
        if !url.isFileURL {
            var headers: [String: String] = [
                "User-Agent": HLSClient.userAgent,
                "Accept": "*/*"
            ]
            if let referer, !referer.isEmpty {
                headers["Referer"] = referer
            }
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.allowsExternalPlayback = true
        player = newPlayer

        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let text = error?.localizedDescription ?? "播放失败"
            Task { @MainActor in
                self.failedText = text
            }
        }

        newPlayer.play()
    }

    private func teardown() {
        player?.pause()
        player = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
    }
}
