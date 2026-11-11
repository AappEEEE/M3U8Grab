import SwiftUI
import WebKit

struct BrowserTab: View {
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @ObservedObject var store: DownloadStore
    @Binding var selectedTab: Int

    @State private var editingAddress = false
    @State private var showSniffedToast = false
    @State private var showPanel = false

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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomToolbar
                }
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
        .sheet(isPresented: $showPanel) {
            SniffedPanelSheet(engine: engine, sniffer: sniffer, store: store, selectedTab: $selectedTab)
        }
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
        .glassSurface(cornerRadius: 19)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
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
            resourcesButton
            toolbarButton("square.and.arrow.up", enabled: engine.currentURL != nil) {
                shareCurrentPage()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .glassSurface(cornerRadius: 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
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

    /// 资源入口：替代原来的页面内悬浮球，数量用角标展示。
    private var resourcesButton: some View {
        Button { showPanel = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "play.square.stack")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .foregroundColor(sniffer.streams.isEmpty ? .secondary.opacity(0.4) : .accentColor)
                if !sniffer.streams.isEmpty {
                    Text("\(sniffer.streams.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: -6, y: 2)
                }
            }
        }
        .disabled(sniffer.streams.isEmpty)
        .accessibilityLabel("本页资源 \(sniffer.streams.count) 个")
    }

    // MARK: - 浮层

    private func interceptedBanner(url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("检测到 M3U8 播放列表")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                Text(url.lastPathComponent.isEmpty ? url.host ?? "" : url.lastPathComponent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            .background(Color.accentColor.opacity(0.16))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
            Button {
                engine.interceptedPlaylist = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .glassSurface(cornerRadius: 16, tint: .accentColor)
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
        .glassSurface(cornerRadius: 16)
    }

    private func sniffToast(_ stream: SniffedStream) -> some View {
        HStack(spacing: 8) {
            Image(systemName: stream.kind.symbol)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("已嗅探到 \(stream.kind.badge)")
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
        .glassSurface(cornerRadius: 16)
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
