import SwiftUI

struct FileBrowserView: View {
    @State private var files: [URL] = []
    @State private var playing: LocalMedia?
    @State private var sharing: SharedFile?

    struct LocalMedia: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        List {
            if files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary)
                    Text("还没有导出文件")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(files, id: \.self) { url in
                    Button {
                        if isPlayable(url) {
                            playing = LocalMedia(url: url)
                        } else {
                            sharing = SharedFile(url: url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isPlayable(url) ? "play.rectangle.fill" : "doc.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .foregroundColor(.primary)
                                Text("\(formatBytes(FileManager.default.fileSize(at: url))) · \(modifiedText(url))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            try? FileManager.default.removeItem(at: url)
                            reload()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            sharing = SharedFile(url: url)
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("本地文件")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $playing) { media in
            PlayerSheet(title: media.url.lastPathComponent, url: media.url, referer: nil)
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: [item.url])
        }
    }

    private func isPlayable(_ url: URL) -> Bool {
        ["mp4", "ts", "mov", "m4v", "mkv"].contains(url.pathExtension.lowercased())
    }

    private func modifiedText(_ url: URL) -> String {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: Paths.downloads,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        files = contents.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l > r
        }
    }
}
