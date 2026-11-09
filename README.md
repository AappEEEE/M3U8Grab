# M3U8 Grab

App Store 上「M3U8 Mpjex」（id6449724938）的无广告平替：**自建源码、可自签安装的 iOS App**。

内置浏览器嗅探 HLS 流 → 播放 / 编辑 / 下载 / 合并导出 MP4 或 TS，附带一个 Safari 扩展做同样的事。

- 无广告、无内购、无账号、无统计上报
- 全部本地处理，下载的文件存在 App 沙盒的 `Downloads` 里，可从「文件」App 直接访问
- 纯 SwiftUI + WebKit + AVFoundation，不使用任何第三方依赖

---

## 1. 功能对照

| 原 App（M3U8 Mpjex） | 本项目 M3U8 Grab | 说明 |
| --- | --- | --- |
| M3U8 Player | ✅ | 内置播放器，直接播远端 m3u8，自动带 UA/Referer |
| Safari Extension | ✅ | 独立的 Safari Web Extension：工具栏弹窗 + **页面右下角悬浮球**，点球直接深链唤起本体下载 |
| 深色模式 | ✅ | 全语义色，跟随系统；扩展弹窗单独适配 `prefers-color-scheme` |
| Sniff / 嗅探 m3u8 | ✅ | 内置浏览器 hook `fetch` / `XHR` / `<video src>` / DOM 变动 / Resource Timing |
| Create M3U8 | ✅ | 「工具 › 手动下载 › 文本模式」可粘贴/编辑播放列表，也可把本地分片合成 |
| Edit M3U8 | ✅ | 文本模式里可直接改内容（改分片顺序、删广告分片、改清晰度地址）再下载 |
| Save M3U8 | ✅ | 下载全部 `.ts` 分片并合并 |
| Save M3U8 to mp4 | ✅ | 合并后走 AVAssetWriter 直通封装成 MP4（不重编码，秒出） |
| Save M3U8 to ts | ✅ | 直接输出 `.ts` |
| 广告 / 弹窗 / 内购 | ❌ | 本项目完全没有 |

额外做的：

- 多清晰度（master playlist）选择，默认选最高码率
- AES-128 加密流解密（`#EXT-X-KEY`，含 `IV` 缺省时按 media sequence 推导）
- fMP4（`#EXT-X-MAP`）流直接拼接
- 断点续传：失败的任务保留已下载分片，重试时跳过已完成的
- 并发数可调（1–16），支持切后台继续跑一小段时间
- 下载完可一键存相册
- 分享/导出到其它 App，或直接在「文件」App 里取
- 剪贴板识别：从 Safari 复制 m3u8 链接，切回 App 自动提示加入（可选开关）
- 深链协议 `m3u8grab://open?url=…`，任何 App / 快捷指令 / 扩展都能把链接推给它

不支持：SAMPLE-AES（DRM）加密流、直播流录制、需要登录 cookie 的付费站点。

---

## 2. 目录结构

```
project.yml                     # XcodeGen 工程定义（唯一工程来源）
Config/
  App-Info.plist                # 主 App 的 Info.plist
  SafariExt-Info.plist          # Safari 扩展的 Info.plist
Sources/
  App/
    AppMain.swift               # @main 入口
    RootView.swift              # 四个 Tab 的根视图
    Models.swift                # 数据模型（SniffedStream / OutputFormat / DownloadPhase ...）
    Utilities.swift             # 沙盒路径、文件名清洗、格式化
    Crypto.swift                # AES-128-CBC 解密（CommonCrypto）
    HLSPlaylist.swift           # m3u8 解析器（master + media，byte-range / key / map）
    HLSClient.swift             # 网络层（UA/Referer/Range）+ 密钥缓存
    DownloadJob.swift           # 单个下载任务的完整状态机
    DownloadStore.swift         # 任务队列 + 状态持久化
    Remuxer.swift               # 分片拼接 + AVAssetWriter 封装 MP4
    MediaSaver.swift            # 存相册
    Sniffer.swift               # 嗅探结果聚合与去重
    BrowserEngine.swift         # WKWebView 封装 + 脚本注入 + 导航拦截
    Resources/injected.js       # 注入到网页的嗅探脚本
    Assets.xcassets/            # AppIcon / AccentColor
    Views/                      # 全部 SwiftUI 视图
  SafariExt/
    SafariWebExtensionHandler.swift
    Resources/                  # manifest.json / background.js / content.js / popup.*
tools/make_icon.py              # 生成 1024 图标
.github/workflows/build-ipa.yml # 云端出未签名 IPA
```

---

## 3. 构建

### 方式 A：GitHub Actions（无需 Mac）

1. 把整个目录推到自己的 GitHub 仓库（public / private 都行）：
   ```bash
   git init
   git add .
   git commit -m "init"
   git branch -M main
   git remote add origin https://github.com/<你>/<仓库>.git
   git push -u origin main
   ```
2. 仓库页面 → **Actions** → 左侧 **Build unsigned IPA** → **Run workflow**。
3. 跑完（约 3–5 分钟）在该次运行底部 **Artifacts** 下载 `M3U8Grab-unsigned-ipa`，里面就是 `M3U8Grab-unsigned.ipa`。

产物是**未签名** IPA，直接装不上，必须自己签一次（见第 4 节）。

> **结论先说：不需要 Mac 也能拿到 IPA。** GitHub Actions 的 `macos-14` runner 就是一台真 Mac + 真 Xcode，编译在云端完成。
> 你本地只要 Windows + 浏览器 + 一个 GitHub 账号，全流程 = 推仓库 → 点 Run workflow → 下 artifact → Sideloadly 签名安装。
> 免费账号每月 2000 分钟额度；macOS runner 按 10 倍计费，一次构建约 5–8 分钟 ≈ 消耗 50–80 分钟额度，跑 20 多次完全够。
> 仓库改成 private 也一样能跑（免费额度相同，private 也能用 Actions 出 artifact）。

### 方式 B：本地 Mac + Xcode

```bash
brew install xcodegen
xcodegen generate            # 生成 M3U8Grab.xcodeproj
open M3U8Grab.xcodeproj
```

在 Xcode 里选中 `M3U8Grab` target → Signing & Capabilities → 勾 Automatically manage signing → 选自己的 Apple ID Team，然后真机运行。

坑位提醒：

- Bundle Identifier 不要用别人的，改成 `com.<你的名字>.m3u8grab`（同时把 `M3U8GrabSafari` 改成 `...m3u8grab.SafariExtension`）。
- 免费 Apple ID 的有效期只有 7 天，重签即可继续用（数据不丢）。
- 免费账号**不支持 App Groups**，所以 Safari 扩展和主 App 之间不共享数据——扩展负责嗅探，复制链接后到主 App「工具 › 手动下载」粘贴，这是刻意设计。

### 方式 C：命令行出 IPA（有 Mac 但不想开 Xcode）

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project M3U8Grab.xcodeproj -scheme M3U8Grab \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  clean build

mkdir -p Payload
cp -R build/DerivedData/Build/Products/Release-iphoneos/M3U8Grab.app Payload/
zip -qry M3U8Grab-unsigned.ipa Payload
```

### 方式 D：VMware 里装 macOS Sonoma 跑 Xcode（备用，完整流程）

这条路能走通，但只建议在「想本地点一下 Run 上真机」或「不想用 GitHub」时才折腾。虚拟机里 Xcode 编译能用，IB 预览和模拟器会明显卡。

**虚拟机侧（宿主机 Windows 上做）**

1. 宿主装 **VMware Workstation 17.5+**（17.0 对 Sonoma 有 CPU 检测问题）；用 **macOS Unlocker / OpenCore 引导 ISO** 打补丁，否则 VMware 不认 macOS 客户机。
2. 新建虚拟机：客户机选 **Apple macOS / macOS 14**，CPU ≥ 4 核，内存 ≥ **8 GB**（16 GB 最舒服），磁盘 ≥ **100 GB**（Xcode + iOS 平台组件就要 40 GB+），显存 512 MB 以上，固件必须 EFI。
3. `vmx` 里补三行再开机，稳定性差别很大：
   ```
   smc.version = "0"
   cpuid.0.eax = "0000:0000:0000:0000:0000:0000:0000:1011"
   board-id.reflectHost = "TRUE"
   ```
4. 装完系统后装 **VMware Tools（darwin.iso）**，显卡加速、共享剪贴板、拖拽拷文件都靠它。
5. 系统设置 → 隐私与安全性 → 允许来自 App Store 和被认可的开发者。

**Xcode 侧（虚拟机里做）**

6. App Store 装 **Xcode 15.4**（Sonoma 14.x 用 15.4 最稳；Xcode 16 要求 macOS 14.5+，也能装）。首次启动会自动要你装 iOS 平台组件，**约 7–10 GB，网速慢会很久**，耐心等或挂代理。
7. 命令行工具就位：
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -version          # 应输出 Xcode 15.4 / Build 15F31d 之类
   xcodebuild -showsdks | grep iphoneos
   ```
8. 装 XcodeGen（二选一）：
   ```bash
   brew install xcodegen                       # 有 Homebrew
   # 或者直接下 release 二进制：https://github.com/yonaskolb/XcodeGen/releases
   ```
9. 生成并打开工程：
   ```bash
   cd /path/to/M3U8Grab
   xcodegen generate
   open M3U8Grab.xcodeproj
   ```
10. Xcode → Settings → **Accounts** → 加自己的 Apple ID（免费 Personal Team 够用，7 天有效）。
11. 选中 **M3U8Grab** target → **Signing & Capabilities** → 勾 *Automatically manage signing* → Team 选你的 Personal Team → **Bundle Identifier 改成唯一值**，例如 `com.yourname.m3u8grab`。
12. 选中 **M3U8GrabSafari** target，做同样三件事：Team 选同一个、Bundle ID 改成 `com.yourname.m3u8grab.SafariExtension`（**必须是主 App 的子标识**，否则装不上）。
13. iPhone 用线连宿主机 → VMware 菜单 **VM › Removable Devices › 你的 iPhone › Connect**（USB 直通），虚拟机的 Finder / Xcode 才会看到设备。
14. 手机上：设置 → 隐私与安全性 → **开发者模式** 打开并重启（iOS 16+ 必须）；然后 设置 → 通用 → VPN与设备管理 → 信任你的证书。
15. Xcode 顶部选你的 iPhone → **⌘R**。第一次会要求手机上点「信任此电脑」。

**只想要 IPA 文件（不上真机）**

第 9 步之后不用管签名，直接：
```bash
xcodebuild -project M3U8Grab.xcodeproj -scheme M3U8Grab \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" clean build
mkdir -p Payload && cp -R build/DerivedData/Build/Products/Release-iphoneos/M3U8Grab.app Payload/
zip -qry M3U8Grab-unsigned.ipa Payload
```
拿到 Windows 上用 Sideloadly 签，或者直接丢进 LiveContainer。

**虚拟机常见坑**

- 卡在苹果 logo / 无限重启：`cpuid` 那三行没加对，或 CPU 虚拟化没在 BIOS 打开（VT-x / AMD-V + IOMMU）。
- Xcode 提示 "Failed to download platform"：网络问题，App Store 里先把 Xcode 装完再让它自己下 iOS 组件；也可以手动去 developer.apple.com 下 Xcode 完整包（含模拟器）。
- USB 直通后 Xcode 看不到设备：先把 iPhone 在宿主机 iTunes 里信任一次，再断开重连到虚拟机；虚拟机 USB 兼容性调成 **USB 3.1**。
- 编译极慢：把虚拟机放 SSD、内存给到 12–16 GB、`xcodebuild` 加 `-jobs 4`，别开模拟器。

---

## 4. 签名安装

### 4.1 Sideloadly（Windows / macOS，最省事）

1. 装 [Sideloadly](https://sideloadly.io/) 和 iTunes（Windows 需要 iTunes 提供驱动）。
2. iPhone 用线连电脑，选设备。
3. IPA 拖进去，Apple ID 填自己的，Start。
4. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。
5. 首次打开 App 若提示「不受信任的开发者」，重复第 4 步。

### 4.2 AltStore / SideStore（自签续期）

装好 AltStore 后，把 IPA 放到「我的 iPhone › AltStore」，AltStore 里点 `+` 选它。免费账号 7 天到期自动续签（需要同一 WiFi 下电脑端 AltServer 在线）。

### 4.3 TrollStore（仅特定系统版本）

如果你的机型 + 系统落在 TrollStore 支持范围（一般是 iOS 14.0–16.6.1 部分版本），可直接装未签名 IPA，永久有效、无需续签。

### 4.4 Xcode 直装

见 3.B，最稳，但需要 Mac。

### 4.5 LiveContainer（不签名，直接跑未签名 IPA）

LiveContainer 的思路是：它自己用 ldid 做**临时签名**，把你的 App 塞进自己的容器里运行，绕开系统安装。所以本项目产出的 **未签名 IPA 正好能用**。

1. 先按 LiveContainer 官方流程装好 LiveContainer（TrollStore / SideStore / AltStore 任一路径）。
2. 把 `M3U8Grab-unsigned.ipa` 传到手机（AirDrop / 文件 App / iCloud）。
3. LiveContainer → 右上 **+** → 选这个 IPA → 等它解包完 → 桌面上出现图标，点开即可。
4. 需要数据持久化就在 LiveContainer 里给这个 App 设置容器名（同一容器名重装不丢数据）。

**必须知道的限制（决定你怎么用这个 App）**：

| 能力 | 装进 LiveContainer 后 |
|---|---|
| 内置浏览器嗅探 m3u8 | ✅ 完全正常，这就是主路径 |
| 下载 / 合并 / 导出 MP4·TS | ✅ 正常（写沙盒目录，Files 里能看到） |
| 存相册 | ✅ 正常（权限弹窗会给） |
| **Safari 扩展（含页面悬浮球）** | ❌ **不会注册** |
| 深链 `m3u8grab://` 唤起 | ⚠️ 大概率无效 |

原因：Safari 扩展是 **App Extension**，要生效必须由系统的 `installd` / `pluginkit` 正式注册进「设置 › Safari › 扩展」列表。LiveContainer 里的 App 是寄生运行，系统根本不知道它的存在，`PlugIns/M3U8GrabSafari.appex` 只会躺在那里没人加载。**这不是代码能解决的，任何 sideload 工具都绕不过去**（TrollStore 装是例外，它走的是真安装）。

所以：**在 LiveContainer 里，请把「内置浏览器」当主功能用**，Safari 扩展那套（悬浮球 / 弹窗 / 深链）当没有。为此本 App 特意做了两条不依赖扩展的通道：

- **工具 › 剪贴板识别**（默认关）：在 Safari 里长按视频或从播放器复制 m3u8 链接 → 切回本 App，顶部自动弹「剪贴板里有 M3U8 链接 → 加入」。
- **工具 › 手动下载**：直接把链接或整段 m3u8 文本贴进来。

---

## 5. 使用流程

### 5.1 嗅探 + 下载（主路径）

1. 「浏览器」Tab，地址栏输入站点地址（不要带 `m3u8`，正常打开视频页面）。
2. 点开视频开始播放，脚本会捕获播放器请求的 m3u8，底部弹「嗅探到 N 个流」。
3. 「嗅探」Tab → 点条目 → 自动解析：类型（master/media）、清晰度数量、分片数、总时长、是否加密。
4. 选清晰度 → 选导出格式（MP4 / TS）→ 开始下载。
5. 「下载」Tab 看进度；完成后可分享、存相册，或去「文件」App 拿文件。

> 若视频被 m3u8 的 mime 直接拦下（`application/vnd.apple.mpegurl`），浏览器会不跳转，顶部出现「拦截到播放列表」横幅，点「下载」即可。

### 5.2 手动下载

「工具」→「手动下载」：

- **链接模式**：粘贴 m3u8 地址（master 或 media 都行）。
- **文本模式**：把整段 m3u8 内容贴进去，填一个基准地址（用于把相对路径拼成绝对地址）。这就是「Create / Edit M3U8」——你可以先删掉广告分片、改顺序，再下载合并。

### 5.3 Safari 扩展（可选，需真安装才能用）

> 前提：App 必须是**系统正式安装**（TrollStore / 付费证书 / 自签后系统安装），LiveContainer 里不会生效，见 4.5。

开启：设置 → Safari → 扩展 → M3U8 Grab → 打开。

**页面悬浮球（对齐原 App 的体验）**

1. 在 Safari 里打开任意视频页面，开始播放（或页面自己加载了播放器）。
2. 一旦嗅到 m3u8，页面右下角浮出一个**蓝色圆球**，右上角红点是数量。
3. 圆球可拖动，位置记在 `localStorage`，刷新还在。
4. **点圆球** → 球上方弹出卡片，列出本页抓到的前 10 条 m3u8（文件名 + 域名）。
5. **点某一条** → 用 `m3u8grab://open?url=…&page=…&title=…` 深链唤起本体 App，自动把这些链接塞进「嗅探」列表，直接就能选清晰度下载。若系统没弹「在 M3U8 Grab 中打开」，说明深链被拉黑，链接会自动复制到剪贴板（回 App 用剪贴板识别或手动下载）。
6. 也可以点 Safari 地址栏左侧的扩展图标，弹窗里每条都有 **在 App 打开 / 复制 / 打开页面** 三个按钮。

> 免费 Apple ID 自签时，Safari 扩展经常不出现在列表里（签名权限限制）。这不是 bug，内置浏览器的嗅探能力完全等价，且体验更顺。

---

## 6. 常见问题

**下载 403 / 分片全部失败**
站点校验 `Referer` 或 `User-Agent`。本项目已自动带上「页面来源的 `scheme://host/`」作为 Referer；若仍失败，把并发降到 2，或换用 Safari 扩展嗅探得到的直链。

**导出的 MP4 在某些播放器黑屏**
说明源流是 MPEG-TS 且音视频参数特殊，直通封装（不重编码）保留了原始参数。用 VLC / Infuse 一般正常；QuickTime 对部分 TS 参数挑剔。想万无一失就选 TS 格式导出。

**提示 SAMPLE-AES 不支持**
该流是 Apple FairPlay 同族的分片级加密，解密需要设备证书链，本项目不做。

**任务失败后重试会不会从头下**
不会。失败任务的工作目录保留在 `Documents/Workspaces/<任务 id>`，重试时已存在的分片直接跳过，只补缺的。

**文件在哪**
「文件」App → 我的 iPhone → M3U8 Grab → Downloads。也可在 App 内「工具 › 本地文件」里管理。

**支持深色模式吗**
全程跟随系统，没有一处写死的浅色背景：

- 界面用的是 SwiftUI 语义色（`.primary` / `.secondary` / `Color(.systemBackground)` / `Color(.secondarySystemBackground)` / `.regularMaterial`），浅色/深色自动切换。
- 内置浏览器设了 `underPageBackgroundColor` 跟随系统，网页加载前和回弹时不闪白。
- 播放器固定深色（`.preferredColorScheme(.dark)`），这是视频播放器的通行做法，避免白底刺眼。
- 扩展弹窗用 CSS `@media (prefers-color-scheme: dark)` 单独配了深色变量；页面悬浮球本身是渐变蓝，两种模式都够对比。
- 想强制某一种：删掉 `Sources/App/AppMain.swift` 里的 `.preferredColorScheme(nil)`，改成 `.light` 或 `.dark`。

**在 LiveContainer 里能用 Safari 扩展吗**
不能，扩展不会注册（原理见 4.5）。内置浏览器嗅探就是替代方案，配套的「剪贴板识别」和「手动下载」让 Safari 里的链接也能进来。

---

## 7. 已知限制

- 部署目标 iOS 15.0；Safari 扩展用 MV2（iOS 15 的 Safari 不认 MV3）。
- 不重编码：`hls.js` 那种拼接后的碎片流不做时间戳修复，极个别源可能音画不同步。
- 直播流（无 `#EXT-X-ENDLIST`）只提示不下载，避免无限下载。
- 免费 Apple ID 签名 7 天过期；扩展与主 App 不共享数据。

---

## 8. 说明

本项目仅用于个人学习与自用备份：解析、合并、导出自己有权访问的媒体流。请遵守目标站点的服务条款与当地法律，不要用于传播受版权保护的内容。
