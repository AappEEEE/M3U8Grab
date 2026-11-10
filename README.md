# M3U8 Grab

一个无广告的 iOS HLS/M3U8 嗅探与下载工具，支持应用内浏览器、Safari 扩展悬浮球、分片合并和导出。

## 下载

当前源码版本为 **v1.2.0（build 3）**，主 App 与 Safari 扩展使用相同版本。打开 [latest 发布页](https://github.com/AappEEEE/M3U8Grab/releases/tag/latest)，下载稳定命名的 **[M3U8Grab.ipa](https://github.com/AappEEEE/M3U8Grab/releases/download/latest/M3U8Grab.ipa)**；同页的 `sha256.txt` 可校验该 IPA。

IPA 是未签名构建。Sideloadly、AltStore/SideStore 等侧载工具按各自流程用个人 Apple ID/证书签名；免费 Apple ID 的签名通常需要定期刷新。Xcode 安装需在 macOS 从源码构建并配置签名。TrollStore 则按其支持的系统版本和安装流程操作，不要求个人 Apple ID 签名。

## 功能

- 内置浏览器：自动识别网页中的 M3U8、TS、MP4 等媒体地址。
- Safari Web Extension：工具栏弹窗列出媒体地址；页面内提供可拖动悬浮球和快速交接到 App 的入口。
- 下载管理：选择清晰度，AES-128 解密，TS 分片合并、fMP4 直拼，导出 MP4/TS、分享或存入相册。
- 稳定性：暂停/继续、已完成分片保留、弱网失败分片延后重试、速度与预计剩余时间。
- 列表效率：分片进度、速度、剩余时间单行显示；按「全部/进行中/已完成」筛选，顶部汇总总速度；支持「继续全部」「暂停全部」。
- 一键下载：在「嗅探」列表右滑即可自动选择最高清晰度并加入下载。
- 手动下载：粘贴 M3U8 地址或播放列表文本。
- 跟随 iOS 深色/浅色外观；无广告、无内购。

## 快速使用

1. 在「浏览器」打开包含视频的网页，等待嗅探结果出现。
2. 进入「嗅探」选择媒体流和清晰度，按需设置 MP4/TS 与并发数后开始下载。
3. 在「下载」列表查看速度和进度；解析/下载阶段可暂停，待「正在停止」结束后继续。合并阶段仅可取消；失败任务可继续重试，已取消任务则重新下载。清理已完成任务会保留暂停/失败任务与已导出文件。
4. 完成后分享/导出，或保存到相册。下载文件也可在「文件」App 的「我的 iPhone › M3U8 Grab › Downloads」查看。

## Safari 扩展与 LiveContainer

App Store 上架应用可以在**同一个主 App 安装包**中包含多个 target，其中 Safari Web Extension 是嵌套的 `.appex`。iOS 安装该主 App 时会登记扩展，用户再到系统 Safari 设置里启用；扩展本身并不是主 App 内的一张网页或一个普通开关。

LiveContainer 的实例化运行方式不会让 iOS 把其中的 appex 注册成系统 Safari 扩展。因此，在 LiveContainer 里开两个实例、并行运行主 App，都不会让系统 Safari 设置出现该扩展，也不能在那里显示 Safari 悬浮球。LiveContainer 中可以使用本 App 的内置浏览器嗅探和下载。要在系统 Safari 用扩展，需要将含 appex 的 App 以能由 iOS 正常安装/登记扩展的方式安装；再在「设置 › App › Safari › 扩展」中启用并授予网站访问权限。若设备的安装方式没有向 iOS 注册 appex，Safari 设置中就不会出现它。

## 当前限制

- 支持常见 VOD HLS 与 AES-128；SAMPLE-AES 暂不支持。
- 依赖网页或 M3U8 地址能直接访问；需要专用登录态、DRM 或受保护播放链路的内容可能无法下载。
- 实时直播列表会持续更新，当前以有限播放列表下载为主，不是持续录制器。
- Safari 扩展与主 App 间通过 URL Scheme 交接链接；免费签名环境下不共享 App Group 数据库。
- IPA 未签名；常规侧载需签名，免费 Apple ID 安装有有效期限制。TrollStore 仅适用于其支持的系统环境。

## 常见问题

**下载遇到断网怎么办？** 已落盘分片保存在任务工作区。恢复网络后点「继续」；未完成分片会再下载，暂时失败的片段会在其余分片完成后低并发重试。重新启动 App 后也可以从任务列表继续。

**Safari 设置里看不到扩展？** 扩展只会在 iOS 把 App 包内的 appex 正常登记后出现。LiveContainer 的实例运行不会完成系统登记；请先确认该安装方式支持 Safari Web Extension，再到 Safari 设置启用。

**MP4 转封装失败？** 任务会尽可能保留 TS 输出；可在分享菜单导出 TS 后用兼容播放器打开。

**怎么加快下载？** 下载设置的并发默认值为 8，可依网络和站点调到 1–16。并发过高可能被服务器限速，慢速或错误率升高时建议降低至 2–4。首轮分片请求超时为 30 秒，单次失败先延后，不堵住其余分片；补片阶段使用更低并发、60 秒超时，每轮最多尝试 2 次，最多 3 轮。持续失败时保留工作区，稍后继续。

## 构建与发布

- 仓库仅保留一个发布 workflow：`.github/workflows/build-ipa.yml`。推送到 `main`/`master`（仅 README 变化除外）自动构建，也支持在这两个分支手动触发。
- CI 在 macOS 上运行 HLS 回归测试、XcodeGen 与未签名 iOS Release 构建，打包前检查 App/扩展均为 `1.2.0 (3)`、扩展根目录 manifest 为 `1.2.0`。
- 验证通过后更新 `latest` 标签到构建提交，覆盖稳定资产 `M3U8Grab.ipa` 与匹配的 `sha256.txt`，并更新发布说明和构建记录；其他分支只构建测试，不发布。
- 发布任务串行执行，避免并发构建互相覆盖资产。

## 反馈

请在 GitHub 仓库提交 issue，并附上 iOS 版本、任务状态、错误信息和相关播放列表类型（请勿上传私人媒体或账号凭据）。
