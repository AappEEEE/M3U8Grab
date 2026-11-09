# M3U8 Grab

一个干净、无广告的 iOS M3U8 下载与播放工具，自带浏览器嗅探与 Safari 扩展。

![platform](https://img.shields.io/badge/platform-iOS%2015.0%2B-blue)
![lang](https://img.shields.io/badge/Swift-5.0-orange)
![ui](https://img.shields.io/badge/SwiftUI-WebKit-purple)
![ads](https://img.shields.io/badge/ads-none-success)
![license](https://img.shields.io/badge/license-MIT-lightgrey)

---

## 这是什么

M3U8 Grab 是一个**纯本地**的 iOS 应用：在内置浏览器里打开任意视频页面，自动嗅探其中的 `m3u8` 播放列表，选中清晰度后把全部分片拉下来、解密、合并，导出为 `mp4` 或 `ts` 文件，存进「文件」App 或相册。

没有广告、没有内购、没有账号、没有数据上报。所有请求都直接发往视频源站，不经过任何中间服务器。

> 如果你的使用场景只是「把网页上的 m3u8 视频存下来离线看」，这个项目就是为它写的。

---

## 功能特性

| 能力 | 说明 |
| --- | --- |
| 🔍 网页嗅探 | 内置 WKWebView，注入脚本钩住 `fetch` / `XMLHttpRequest` / `HTMLMediaElement.src` / `setAttribute` / `MutationObserver` / `PerformanceObserver`，任何出现在页面里的 m3u8 和直链视频都会被捕获 |
| 🧩 Safari 扩展 | 独立扩展 target，工具栏弹窗列清单，页面右下角还有一颗可拖动的悬浮球，点一下直接跳进 App 下载 |
| 🎚 多清晰度 | 解析 Master Playlist，列出全部 `EXT-X-STREAM-INF` 变体（分辨率 / 码率 / 编码），默认选码率最高的一档 |
| 🔐 AES-128 解密 | 支持 `#EXT-X-KEY:METHOD=AES-128`，自动按 `IV` 或媒体序列号推导初始向量后解密 |
| 🧱 fMP4 直拼 | 识别 `#EXT-X-MAP` 初始化段，把 init + 分片原样拼成可播放的 mp4，无需转封装 |
| 📦 导出 TS | 不想转封装就直接交付 `ts`，兼容性最好、速度最快 |
| 🎬 转封装 MP4 | 用 `AVAssetReader` + `AVAssetWriter` 做 passthrough remux，不重新编码，几乎无损且速度快 |
| ⏯ 边下边播 | 嗅探到的地址可以直接用内置播放器预览，请求会带上页面 Referer 与 UA，绕开常见的防盗链 |
| ♻️ 断点续传 | 失败的任务会保留工作目录，重试时已下载的分片自动跳过 |
| ⚡️ 并发下载 | 1–16 路并发可调，默认 6 路 |
| 📋 剪贴板识别 | 开启后回到 App 时自动识别剪贴板里的 m3u8 链接，一键加入嗅探列表 |
| 🔗 深链协议 | `m3u8grab://open?url=…&page=…&title=…`，可被 Safari 扩展、快捷指令或其他 App 调用 |
| 🌗 深色模式 | 全语义色实现，跟随系统深浅色 |
| 🗂 文件管理 | 下载结果落在「文件」App 的 `M3U8 Grab/Downloads`，可直接播放、分享、隔空投送 |
| 🖼 存相册 | 可选下载完成后自动保存到相册 |

---

## 和 App Store 版本的区别

本项目是「M3U8 Mpjex」这类付费/带广告工具的**开源自建替代品**，功能对照如下：

| 能力 | 商业版 | 本项目 |
| --- | --- | --- |
| M3U8 播放 | ✅ | ✅ |
| 嗅探网页视频 | ✅ | ✅（内置浏览器 + Safari 扩展） |
| 创建 / 编辑播放列表 | ✅ | ✅（手动下载页可直接编辑文本） |
| 保存为 TS | ✅ | ✅ |
| 保存为 MP4 | ✅ | ✅ |
| 多清晰度选择 | 部分版本 | ✅ |
| AES-128 解密 | 部分版本 | ✅ |
| 断点续传 | ❌ | ✅ |
| 广告 | 有 | **无** |
| 内购 / 订阅 | 有 | **无** |
| 数据上报 | 有 | **无** |
| 源码 | 闭源 | **MIT 开源** |

不支持的能力（两边都可能不支持，明确写在这里避免误会）：

- `SAMPLE-AES` —— 需要设备级解密，纯软件实现不了
- Widevine / FairPlay 等 DRM 流 —— 加密密钥不在客户端
- 直播录制 —— 只处理有 `#EXT-X-ENDLIST` 的点播列表
- 需要登录 Cookie 才能访问的付费站 —— 分片请求不带浏览器的登录态

---

## 下载与安装

### 获取 IPA

从本仓库的 [Releases](https://github.com/AappEEEE/M3U8Grab/releases) 下载最新的 `M3U8Grab.ipa`。下载后使用下方任一种方式签名并安装到 iPhone。

> Releases 中的 IPA 由 GitHub Actions 自动构建并发布，属于未签名版本；安装前需用自己的 Apple ID 或签名证书完成签名。

## 安装到 iPhone

从 [Releases](https://github.com/AappEEEE/M3U8Grab/releases) 下载 `M3U8Grab.ipa` 后，按你的条件选一条路：

| 方式 | 需要 | 有效期 | 说明 |
| --- | --- | --- | --- |
| **Sideloadly** | Windows / macOS + Apple ID | 7 天（免费账号） | 最通用，电脑上拖入 IPA 输入 Apple ID 即可，到期重签 |
| **AltStore / SideStore** | 一台常开的电脑或同一 WiFi | 7 天自动续签 | 装一次之后自动重签，省心 |
| **TrollStore** | 特定 iOS 版本（14.0–16.6.1 等） | 永久 | 真正安装，扩展可正常注册 |
| **Xcode 直装** | Mac | 7 天 | 开发调试最方便，⌘R 即可 |
| **LiveContainer** | 已越狱或 TrollStore 环境 | 取决于容器 | 寄生运行，**不支持** Safari 扩展，见下表 |

### LiveContainer 里的能力边界

| 能力 | 是否可用 | 原因 |
| --- | --- | --- |
| 内置浏览器嗅探 | ✅ | 纯 App 内逻辑 |
| 下载 / 合并 / 导出 | ✅ | 纯 App 内逻辑 |
| 存相册 | ✅ | 系统相册权限 |
| Safari 扩展（含悬浮球） | ❌ | appex 必须由系统 `installd` / `pluginkit` 注册，寄生容器里的包系统不知道 |
| 深链 `m3u8grab://` | ⚠️ 大概率无效 | 同上，URL scheme 未注册到系统 |

结论：**想用 Safari 扩展，就必须真正安装**（TrollStore / 自签 / 开发者证书）；只想下载视频，LiveContainer 完全够用。

---

## 使用指南

### 1. 嗅探下载（主流程）

1. 打开 App 的「浏览器」标签页，输入视频页面地址
2. 播放视频，页面里出现的 m3u8 会被自动捕获，底部会弹出提示
3. 切到「嗅探」标签页，点进目标记录
4. 如果是多清晰度，选择想要的一档；设置导出格式（MP4 / TS）与并发数
5. 点「开始下载」，在「下载」标签页看进度
6. 完成后文件在「文件」App → `我的 iPhone` → `M3U8 Grab` → `Downloads`

### 2. 手动下载

已知 m3u8 地址，或者从别处复制来一段播放列表文本：

- **链接模式**：粘贴 URL，支持直接粘贴带参数的完整地址
- **文本模式**：把 `#EXTM3U …` 全文贴进来，填一个基准地址用于解析相对路径；可以在这一步直接改内容（换清晰度、删广告分片）

### 3. Safari 扩展

真正安装后（自签或 TrollStore）：

1. 设置 → Safari → 扩展 → 打开 **M3U8 Grab**
2. 允许访问「所有网站」
3. 在 Safari 打开视频页，工具栏点扩展图标，或者点页面右下角的**悬浮球**
4. 列表里选一条 → 「在 App 打开」→ 自动跳转 App 并开始下载
5. 悬浮球可以拖动，位置会被记住

> 扩展与主 App 之间不使用 App Group（免费 Apple ID 签名不支持），所以数据不共享，靠 URL scheme 交接。

### 4. 剪贴板与深链

- 工具页可开启「识别剪贴板里的 M3U8 链接」，回到 App 时自动弹横幅
- 任何地方都能用 `m3u8grab://open?url=<编码后的地址>&page=<来源页>&title=<标题>` 唤起 App

---

## 常见问题

**Q：下载时报 403 / 401？**
源站校验了 Referer 或 UA。确认是从页面里嗅探出来的记录（会带上来源页 Referer），或者手动下载时把「来源页」填对。部分站点还校验 Cookie，这种无解。

**Q：导出的 MP4 在黑屏 / 只有声音？**
说明源是 TS 分片且编码参数特殊，`AVAssetWriter` passthrough 失败了——任务会保底交付一个 `.ts` 文件，直接播放或换播放器即可。想要更稳，就在下载设置里直接选 TS。

**Q：卡在「合并中」很久？**
大文件 remux 需要读写几个 GB，慢是正常的。也可以直接选 TS 格式，跳过转封装。

**Q：能下直播吗？**
不能。直播没有 `#EXT-X-ENDLIST`，分片是无限追加的。

**Q：为什么提示 SAMPLE-AES 不支持？**
这种流每个分片用不同的密钥，且需要设备级解密密钥，纯 App 内无法完成。

**Q：下载中断了要重来吗？**
不用。失败的任务会保留工作目录，点「重试」会跳过已下载的分片继续。

**Q：文件存在哪？**
App 沙盒的 `Documents/Downloads`，已开启文件共享，所以在「文件」App 里能看到，也可以直接拖到电脑。

**Q：支持深色模式吗？**
支持，全部用语义色实现，跟随系统。播放页固定深色（视频播放器的惯例）。

**Q：为什么要用内置浏览器，不能直接用 Safari？**
两者都行。内置浏览器的好处是嗅探与下载在同一个 App 内闭环，不需要来回切；Safari 扩展更适合边浏览边收集。

---

## 技术实现

```
网页 / Safari
   │  JS 钩子（fetch、XHR、media.src、MutationObserver、resource timing）
   ▼
Sniffer（去重、来源页、Referer 推导）
   │
   ▼
HLS 解析（HLSParser：Master / Media、EXT-X-KEY、EXT-X-MAP、BYTERANGE、序列号）
   │
   ▼
并发下载（TaskGroup，可配 1–16，失败 3 次退避重试，已存在分片跳过）
   │
   ├─ AES-128 → CommonCrypto CBC 解密 + 手工去 PKCS7
   ├─ fMP4（有 EXT-X-MAP）→ init + 分片直拼
   └─ TS → 直拼 merged.ts → AVAssetReader/Writer passthrough 转 mp4
   │
   ▼
Documents/Downloads + 可选存入相册 + 任务状态持久化（state.json）
```

几个实现上的取舍：

- **不用 App Group**：免费签名不支持，改成 URL scheme 交接，代价是扩展与 App 数据不共享
- **不引入第三方依赖**：HLS 解析、解密、remux 全部手写，避免 SPM 依赖在未签名环境下出问题
- **XcodeGen 作为唯一工程来源**：`.xcodeproj` 不入库，避免 merge 冲突，也方便脚本化构建
- **SWIFT_VERSION 5.0 + `@MainActor` 类**：绕开 Swift 6 严格并发的可用性坑，同时保证 UI 更新都在主线程

---

## 目录结构

```
.
├── project.yml                      # XcodeGen 工程定义（唯一来源）
├── Config/
│   ├── App-Info.plist               # 主 App：文件共享、相册权限、URL scheme、ATS
│   └── SafariExt-Info.plist         # 扩展：NSExtension 声明与站点访问权限
├── Sources/
│   ├── App/
│   │   ├── AppMain.swift            # @main 入口
│   │   ├── RootView.swift           # 四标签页、深链、剪贴板识别
│   │   ├── Models.swift             # 数据模型
│   │   ├── Sniffer.swift            # 嗅探结果收集与去重
│   │   ├── BrowserEngine.swift      # WKWebView 封装、注入脚本、导航拦截
│   │   ├── HLSPlaylist.swift        # 播放列表解析
│   │   ├── HLSClient.swift          # 网络层与密钥缓存
│   │   ├── Crypto.swift             # AES-128 CBC
│   │   ├── DownloadJob.swift        # 单个下载任务的状态机
│   │   ├── DownloadStore.swift      # 任务队列、并发、持久化
│   │   ├── Remuxer.swift            # TS → MP4 转封装
│   │   ├── MediaSaver.swift         # 存入相册
│   │   ├── Utilities.swift          # 路径、格式化、剪贴板等
│   │   ├── Views/                   # 全部 SwiftUI 界面
│   │   ├── Resources/injected.js    # 注入到网页的嗅探脚本
│   │   └── Assets.xcassets/         # AppIcon 与强调色
│   └── SafariExt/
│       ├── SafariWebExtensionHandler.swift
│       └── Resources/               # manifest.json / content.js / background.js / popup.*
├── tools/make_icon.py               # 用 Pillow 生成 AppIcon
└── .github/workflows/build-ipa.yml  # 出未签名 IPA 的 CI
```

---

## 自定义

| 想改什么 | 改哪里 |
| --- | --- |
| 首页地址 | `BrowserEngine.swift` 里的 `GrabConstants.homeURLString` |
| 默认并发 | `DownloadStore.swift` 的 `concurrency = 6` |
| 嗅探逻辑（多抓点东西） | `Sources/App/Resources/injected.js` 与 `Sources/SafariExt/Resources/content.js` |
| 悬浮球样式 | `Sources/SafariExt/Resources/content.js` 里的 `ensureBall()` |
| App 图标 | 改 `tools/make_icon.py` 后运行，或直接替换 `Icon-1024.png` |
| 包名 / 版本号 | `project.yml` 的 `settings.base` |
| 部署目标 | `project.yml` 的 `options.deploymentTarget.iOS` |

---

## 已知限制

- 未签名 IPA 只能用 7 天（免费 Apple ID），需要重签
- 免费签名不支持 App Groups、推送、iCloud 能力
- 部分站点对分片做 IP 绑定或短时效签名，下载到一半会失效
- `SAMPLE-AES`、DRM、直播录制不支持
- 内置浏览器是 WKWebView，个别依赖特殊 Web API 的站点可能表现异常

---

## 免责声明

本项目仅供个人学习与技术研究使用。请只下载你有权访问、且版权方允许离线保存的内容；**不要**用于传播盗版、二次分发或任何商业用途。使用者需自行承担因使用本工具产生的一切法律责任，作者不对任何滥用行为负责。

如果某个站点或内容方不希望被此工具访问，请自行停止使用。

---

## License

MIT
