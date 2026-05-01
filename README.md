# 🏎️ Velocity

**Velocity** is a sleek, minimal macOS GUI for `lftp`, the sophisticated command-line file transfer program.

While `lftp` is widely considered one of the fastest and most reliable transfer tools - thanks to its support for segmented and parallel downloads - it has historically lacked a native, modern interface for macOS. Velocity bridges that gap, bringing the raw power of the command line to a refined, dual-pane SwiftUI experience.

## ✨ Features

- **Segmented Downloads:** Break single large files into multiple parts to saturate your bandwidth.
- **Parallel Transfers:** Transfer multiple files simultaneously using `lftp`'s robust queue management.
- **SwiftUI Native:** Built from the ground up using Apple's latest design principles (HIG) for a light, responsive, and truly "Mac-like" feel.
- **Dual-Pane Navigation:** A classic, efficient side-by-side layout for local and remote file systems.
- **Open Source:** Designed for the community, by the community. No App Store bloat, just a clean tool you can download and run.

## 🤔 Why Velocity?

Standard FTP clients often prioritize features over performance, or they use proprietary engines that don't match the throughput of `lftp`. By wrapping the `lftp` CLI, Velocity inherits decades of networking optimization, including:

- **The `mirror` command:** Effortlessly sync entire directory trees.
- **Protocol Versatility:** Native support for FTP, SFTP, HTTP, and more.
- **Resilience:** Automatic retries and persistence for interrupted transfers.

## 🛠️ Built With

- **SwiftUI:** For a modern, declarative UI.
- **Swift Concurrency:** Leveraging `async/await` to keep the interface fluid while managing heavy CLI processes.
- **`lftp`:** The world-class file transfer utility.

## 🚧 Status: Work in Progress

Velocity is currently an **experimental, early-stage project**. While the core mechanics and UI are taking shape, please note that it is under active development. Some features may be incomplete or subject to change.

## 🚀 Getting Started

### Prerequisites

You must have `lftp` installed via Homebrew:

```
brew install lftp
```

### Installation

1. Clone the repository: `git clone https://github.com/jslpc/Velocity`
2. Open `Velocity.xcodeproj` in Xcode.
3. Build and Run.

## 🗺️ Roadmap

- [ ] Secure Keychain integration for credential storage (including ssh keys.)
- [ ] Interactive progress bars for segmented chunks.
- [ ] Drag-and-drop support from Finder.
- [ ] Customizable `lftp` flag overrides for advanced users.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/jslpc/Velocity/issues).

---

_Velocity is an independent open-source project and is not affiliated with the original lftp authors._
