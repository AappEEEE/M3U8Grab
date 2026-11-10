import SwiftUI

struct ToolsTab: View {
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @ObservedObject var store: DownloadStore

    @AppStorage("clipboardWatch") private var clipboardWatch = false

    @State private var showClearCacheConfirm = false
    @State private var clearing = false
    @State private var copiedBookmarklet = false
    @State private var fileCount = 0
    @State private var totalSize: Int64 = 0

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        ManualDownloadView(store: store)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("手动下载")
                                Text("粘贴 m3u8 链接或整段播放列表文本")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                } header: {
                    Text("下载")
                }

                Section {
                    NavigationLink {
                        FileBrowserView()
                    } label: {
                        HStack {
                            Label("本地文件", systemImage: "folder")
                            Spacer()
                            Text("\(fileCount) 个 · \(formatBytes(totalSize))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("导出")
                } footer: {
                    Text("路径：文件 › 我的 iPhone › M3U8 Grab › Downloads")
                }

                Section("下载设置") {
                    Stepper(value: $store.concurrency, in: 1...16) {
                        HStack {
                            Text("并发分片数")
                            Spacer()
                            Text("\(store.concurrency)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Toggle("完成后自动保存到相册", isOn: $store.autoSaveToPhotos)
                }

                Section {
                    Toggle(isOn: $sniffer.isSniffingEnabled) {
                        Label("嗅探开关", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Toggle(isOn: $clipboardWatch) {
                        Label("识别剪贴板里的 M3U8 链接", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        HStack {
                            Label("清除网页数据与嗅探记录", systemImage: "trash")
                            Spacer()
                            if clearing { ProgressView() }
                        }
                    }
                } header: {
                    Text("浏览器")
                } footer: {
                    Text("清除后会退出所有网站登录状态，嗅探列表也会清空。\n开启剪贴板识别后，从 Safari 复制 m3u8 链接再切回本 App 会自动提示；iOS 16 起首次读取会弹一次系统「允许粘贴」确认。")
                }

                Section {
                    Button {
                        copyToPasteboard(Bookmarklet.code)
                        copiedBookmarklet = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedBookmarklet = false }
                    } label: {
                        Label(copiedBookmarklet ? "已复制，去 Safari 新建书签" : "复制书签小工具代码",
                              systemImage: copiedBookmarklet ? "checkmark.circle.fill" : "bookmark")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("1. 在 Safari 打开任意网页，点分享 › 添加书签")
                        Text("2. 书签地址换成刚复制的代码（以 javascript: 开头）")
                        Text("3. 播放视频后点该书签，页面右下角会出现资源面板")
                        Text("4. 点条目复制链接，切回本 App 自动识别并提示加入")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
                } header: {
                    Text("Safari 悬浮球（书签版，免扩展）")
                } footer: {
                    Text("LiveContainer 里运行的 App 不会把扩展注册进 Safari，书签小工具绕开这个限制：它完全在网页里执行，不需要扩展、不需要签名权限。使用前请在下面开启「识别剪贴板里的 M3U8 链接」。")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 设置 › Safari 浏览器 › 扩展 › M3U8 Grab 打开")
                        Text("2. 在 Safari 里播放视频，点地址栏左侧的扩展图标")
                        Text("3. 复制抓到的 m3u8 地址，回到本 App「手动下载」粘贴")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("Safari 扩展")
                } footer: {
                    Text("用免费 Apple ID 自签安装时，扩展可能不显示；内置浏览器右下角悬浮球与书签版不依赖扩展，功能完全一样。")
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        UIApplication.shared.open(URL(string: "https://github.com")!)
                    } label: {
                        Label("开源说明", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("工具")
            .onAppear(perform: refreshFiles)
            .alert("清除网页数据？", isPresented: $showClearCacheConfirm) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    clearing = true
                    Task {
                        await engine.clearWebsiteData()
                        sniffer.clear()
                        clearing = false
                    }
                }
            } message: {
                Text("将删除 Cookie、缓存与全部嗅探记录。")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func refreshFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Paths.downloads,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        fileCount = files.count
        totalSize = files.reduce(Int64(0)) { partial, url in
            partial + FileManager.default.fileSize(at: url)
        }
    }
}
