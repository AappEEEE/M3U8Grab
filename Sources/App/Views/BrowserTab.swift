import SwiftUI
import WebKit

struct BrowserTab: View {
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @Binding var selectedTab: Int

    @State private var editingAddress = false
    @State private var showSniffedToast = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                addressBar
                if engine.isLoading {
                    ProgressView(value: engine.progress)
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                }

                ZStack(alignment: .bottom) {
                    WebViewContainer(engine: engine)
                        .ignoresSafeArea(.container, edges: .bottom)

                    VStack(spacing: 8) {
                        if let playlist = engine.interceptedPlaylist {
                            interceptedBanner(url: playlist)
                        }
                        if let error = engine.lastError {
                            errorBanner(text: error)
                        }
                        if showSniffedToast, let latest = sniffer.streams.first {
                            sniffToast(latest)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }

                bottomToolbar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(engine.pageTitle.isEmpty ? (engine.currentURL?.host ?? "M3U8 Grab") : engine.pageTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let host = engine.currentURL?.host, !engine.pageTitle.isEmpty {
                            Text(host)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        selectedTab = 1
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("\(sniffer.streams.count)")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(sniffer.streams.isEmpty ? .secondary : .accentColor)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: sniffer.streams.count) { newValue in
            guard newValue > 0 else { return }
            withAnimation(.easeOut(duration: 0.2)) { showSniffedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeIn(duration: 0.2)) { showSniffedToast = false }
            }
        }
    }

    // MARK: - 地址栏

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("输入网址或 m3u8 链接", text: $engine.addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit {
                    engine.load(engine.addressText)
                    hideKeyboard()
                }
                .onTapGesture { editingAddress = true }
            if !engine.addressText.isEmpty {
                Button {
                    engine.addressText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            if engine.isLoading {
                Button {
                    engine.stopLoading()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                }
            } else {
                Button {
                    engine.load(engine.addressText)
                    hideKeyboard()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - 底部工具条

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("chevron.left", enabled: engine.canGoBack) { engine.goBack() }
            toolbarButton("chevron.right", enabled: engine.canGoForward) { engine.goForward() }
            toolbarButton("house", enabled: true) { engine.goHome() }
            toolbarButton(engine.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                engine.isLoading ? engine.stopLoading() : engine.reload()
            }
            toolbarButton("square.and.arrow.up", enabled: engine.currentURL != nil) {
                shareCurrentPage()
            }
        }
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func toolbarButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .foregroundColor(enabled ? .primary : .secondary.opacity(0.4))
        }
        .disabled(!enabled)
    }

    // MARK: - 浮层

    private func interceptedBanner(url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("检测到 M3U8 播放列表")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                Text(url.lastPathComponent.isEmpty ? url.host ?? "" : url.lastPathComponent)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
            Button("下载") {
                engine.interceptedPlaylist = nil
                selectedTab = 1
            }
            .font(.footnote.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.22))
            .foregroundColor(.white)
            .clipShape(Capsule())
            Button {
                engine.interceptedPlaylist = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard let playlist = engine.interceptedPlaylist else { return }
            engine.notePlaylist(playlist)
            selectedTab = 1
        }
    }

    private func errorBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(3)
            Spacer()
            Button {
                engine.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sniffToast(_ stream: SniffedStream) -> some View {
        HStack(spacing: 8) {
            Image(systemName: stream.kind == .hls ? "play.rectangle.on.rectangle" : "doc")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("已嗅探到 \(stream.kind == .hls ? "M3U8" : "媒体文件")")
                    .font(.caption.weight(.semibold))
                Text(stream.url.lastPathComponent.isEmpty ? (stream.url.host ?? "") : stream.url.lastPathComponent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("查看") { selectedTab = 1 }
                .font(.caption.weight(.bold))
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selectedTab = 1 }
    }

    private func shareCurrentPage() {
        guard let url = engine.currentURL else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.present(activity, animated: true)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
