# Spotify 歌词助手 (SpotifyLyricsAssistant)

<div align="center">
  <img src="assets/icon.png" width="150" height="150" alt="App Icon">
</div>

一个 macOS 原生桌面歌词悬浮窗应用，为 Spotify 用户提供类似 QQ 音乐 / 酷狗音乐的桌面歌词助手功能。

## ✨ 功能特性

- 🪟 **桌面歌词悬浮窗** — 毛玻璃效果（macOS 原生 Liquid Glass），始终置顶显示，可自由拖拽调整位置和大小
- 📊 **状态栏歌词** — 在 macOS 状态栏中滚动显示当前歌词行
- 🔄 **实时同步** — 歌词与 Spotify 播放进度精准同步（误差 < 500ms）
- ⏱️ **歌词时间微调** — 支持在悬浮窗内一键“快/慢”调节时间偏移，拯救时间轴不准的歌词
- 🔍 **自动匹配歌词** — 三级歌词源自动降级：LRCLib → 网易云音乐 → QQ 音乐
- 💾 **智能本地缓存** — 歌词自动缓存（LRU 最大 500 首/30天过期），极致秒开、告别重复请求
- ⚙️ **丰富定制性** — 动态读取系统字体一键切换，支持无级调节透明度及字体大小

## 🔧 系统要求

- macOS 15 (Sequoia) 或更高版本
- Spotify macOS 客户端（需要运行中）

## 🚀 快速开始

### 使用 Xcode 打开

```bash
cd SpotifyLyricAssitent
python3 generate_xcodeproj.py   # 生成 Xcode 项目（仅第一次或添加新文件后需要）
open SpotifyLyricsAssistant.xcodeproj
```

然后在 Xcode 中按 `⌘R` 运行。

### 首次运行

1. 启动 App 后，菜单栏会出现 🎵 图标
2. 打开 Spotify 并开始播放音乐
3. 歌词悬浮窗将自动出现并同步显示歌词
4. 首次运行时，macOS 会请求允许 App 控制 Spotify — 请点击"好"

## 📁 项目结构

```
SpotifyLyricsAssistant/
├── Models/
│   ├── Track.swift              # 曲目信息模型
│   ├── LyricsLine.swift         # 歌词行模型
│   └── AppSettings.swift        # 用户设置模型
│
├── ViewModels/
│   ├── PlayerViewModel.swift    # 播放状态 + 歌词同步（核心）
│   └── SettingsViewModel.swift  # 设置管理
│
├── Services/
│   ├── SpotifyBridge.swift      # AppleScript 与 Spotify 通信
│   ├── LyricsCoordinator.swift  # 歌词源协调器（降级策略）
│   ├── LyricsCache.swift        # 本地歌词缓存
│   └── Providers/
│       ├── LRCLibProvider.swift      # LRCLib.net（首选）
│       ├── NeteaseProvider.swift     # 网易云音乐（次选）
│       └── QQMusicProvider.swift     # QQ 音乐（第三选）
│
├── Utilities/
│   └── LRCParser.swift          # LRC 格式解析器
│
└── Views/
    ├── FloatingWindow/
    │   ├── FloatingLyricsPanel.swift  # NSPanel 悬浮窗
    │   ├── LyricsWindowView.swift     # 悬浮窗内容视图
    │   └── LyricsScrollView.swift     # 歌词滚动列表
    │
    ├── MenuBar/
    │   ├── MenuBarLabelView.swift     # 状态栏歌词 Marquee
    │   └── MenuBarMenuView.swift      # 状态栏下拉菜单
    │
    └── Settings/
        └── SettingsView.swift         # 偏好设置界面
```

## 🏗️ 架构说明

### 数据流

```
Spotify App
    │ AppleScript (每 500ms)
    ▼
SpotifyBridge (Actor)
    │
    ▼
PlayerViewModel (@MainActor ObservableObject)
    │                        │
    ├── 曲目变化 →           └── 位置更新 (每 500ms)
    │   LyricsCoordinator              │
    │   ├── LRCLib                     ▼
    │   ├── Netease         updateCurrentLine()
    │   └── QQMusic                    │
    │   (+ LyricsCache)                ▼
    │                       currentLineIndex @Published
    ▼                                  │
  lyrics @Published                    │
    │                                  │
    └──────────────────────────────────┘
                    │
                    ▼
         SwiftUI Views (自动重渲染)
         ├── LyricsScrollView (悬浮窗)
         └── MenuBarLabelView (状态栏)
```

### 关键设计决策

| 决策 | 原因 |
|------|------|
| 使用 AppleScript 而非 Web API | 无需 OAuth 授权，本地直接查询，延迟更低 |
| 双频率轮询（2s/0.5s） | 曲目变化检测和位置同步对实时性要求不同 |
| Actor 隔离 SpotifyBridge | AppleScript 是阻塞调用，必须在后台线程执行 |
| NSPanel 而非 SwiftUI Window | NSPanel 支持非激活、透明、置顶等精细控制 |
| 三级歌词源 | 覆盖不同语言/地区的歌曲，无需任何 API key |

## 🔒 权限说明

首次运行时，App 会请求以下权限：

- **自动化权限（Spotify）** — 用于 AppleScript 查询当前播放信息
- **网络访问** — 用于从 LRCLib、网易云音乐、QQ 音乐获取歌词

App **不会**收集任何个人数据，所有数据仅在本地处理。

## 🛠️ 开发说明

### 添加新文件后更新 Xcode 项目

```bash
python3 generate_xcodeproj.py
```

### 清除歌词缓存

在 App 内：状态栏菜单 → 设置 → 歌词来源 → 清除歌词缓存

### 调试歌词同步

如果歌词与音乐不同步，可在设置 → 高级 → 歌词时间偏移中调整。

## 📄 开源协议

MIT License — 欢迎 Fork 和贡献！
