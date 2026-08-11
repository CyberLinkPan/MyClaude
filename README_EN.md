<div align="center">

<img src="docs/icon.png" width="128" alt="MyClaude icon (pixel Clawd)">

# MyClaude

**A liquid-glass Claude Code usage dashboard for the macOS menu bar**

Track your Claude Code token consumption in real time — today / this week / 90-day heatmap /
model breakdown / 5-hour window / cache hit rate — rendered on frosted glass that lets your wallpaper shine through.

English | [简体中文](README.md)

[![Release](https://img.shields.io/github/v/release/CyberLinkPan/MyClaude?color=5ac8fa&label=Release)](../../releases/latest)
[![Downloads](https://img.shields.io/github/downloads/CyberLinkPan/MyClaude/total?color=5ac8fa&label=Downloads)](../../releases)
[![Build](https://github.com/CyberLinkPan/MyClaude/actions/workflows/build.yml/badge.svg)](../../actions)
[![License](https://img.shields.io/github/license/CyberLinkPan/MyClaude?color=5ac8fa)](LICENSE)
![Platform](https://img.shields.io/badge/macOS%2013%2B-Apple%20Silicon-5ac8fa)

`Swift` · `SwiftUI` · `zero dependencies` · `fully local`

<img src="docs/dashboard-v1.png" width="820" alt="Dashboard">

</div>

---

## ✨ Features

- **Lives in your menu bar** — click the pixel-art Clawd icon for a frosted-glass stats panel
- **Full dashboard** — 4 stat cards + 4 tabs (Today / Trends / Projects / 5h Window) with a **draggable liquid-glass segmented control**
- **14 hand-crafted modules**, independently configurable for the popover and the dashboard:
  weekly-quota ring · goals · 90-day heatmap (hot cells sparkle ✨) · last 7 days · next reset ·
  health check · model breakdown · speedometer gauge · live pulse (per-minute spectrum) ·
  24-hour clock ring · weekday rose chart · odometer milestones · **cache hit rate** · GitHub repos
- **Dynamic light effects** (15 individual switches) — twinkling heatmap cells, comets with trails
  cruising along curves, glowing dots patrolling progress bars, energy bands rising through bar charts,
  sonar pings sweeping rose petals — all with randomized phases, and idle-free when panels are hidden
- **Liquid-glass UI** — desktop-level blur via `NSVisualEffectView`; card borders carry specular highlights
- **Themeable** — 8 presets + free color picking; ring / curves / heatmap gradients all derive automatically; adjustable glass tint
- **GitHub device-flow login** — one click, authorize in the browser, token stored in the macOS Keychain
- **Hover tooltips** — hover any module chip in Settings for a detailed explanation
- **Bilingual UI** — switch between System / 中文 / English in Settings; every string and date format updates live

## 📸 Screenshots

| Menu bar popover | Fancy modules |
|---|---|
| <img src="docs/popover-v1.png" width="380"> | <img src="docs/modules.png" width="380"> |

| Theme: neon pink (default) | Theme: deep-sea blue |
|---|---|
| <img src="docs/theme-pink.png" width="380"> | <img src="docs/theme-blue.png" width="380"> |

> Screenshots are offscreen renders with real data; on a real desktop the background is
> true frosted glass and every light effect is animated.

## 🚀 Install

### Option 1: Download a Release (recommended)

1. Grab `MyClaude.zip` from [Releases](../../releases), unzip
2. Drag `MyClaude.app` into Applications
3. **First launch: right-click → Open → Open** (the app is not notarized; this is needed once)
4. The pixel Clawd appears in your menu bar

> Requires: Apple Silicon Mac (M1+) · macOS 13+ · [Claude Code](https://claude.com/claude-code) installed and used at least once

### Option 2: Build from source

Only Xcode Command Line Tools required (no full Xcode):

```bash
git clone https://github.com/CyberLinkPan/MyClaude.git
cd MyClaude
./build.sh
open MyClaude.app
```

> `build.sh` includes an automatic workaround (VFS overlay + explicit module build) for a
> broken-CLT state where `SwiftBridging` is defined twice; it is harmless on healthy toolchains.
> It also creates a stable self-signed identity `MyClaude Dev` in your login keychain so Keychain
> permissions survive rebuilds.

## 📊 Data & Privacy

- Data source: your local `~/.claude/projects/**/*.jsonl` (Claude Code session logs), deduplicated by `message.id + requestId`
- Counting: **input + output + cache write + cache read**, refreshed incrementally every 30 s
- **Fully local** — usage data never leaves your machine; only token counts, model names, timestamps and
  project paths are parsed, never conversation content
- The only network feature is the optional GitHub module (api.github.com); credentials live in the macOS Keychain
- Daily goal / weekly budget are user-defined estimates — Anthropic does not publish token-denominated limits

## ❓ FAQ

**"App is damaged / unidentified developer"** — right-click → Open, or System Settings → Privacy & Security → Open Anyway, or `xattr -cr /Applications/MyClaude.app`

**No menu bar icon?** — a crowded menu bar hides icons behind the notch; ⌘-drag some icons away, or double-click the app to open the dashboard directly

**Keychain prompt about confidential information?** — macOS re-confirms access to your stored GitHub credential when the app's signing identity changes (first run / update). Enter your login password and click **Always Allow** — once per version. Users who never connect GitHub never see it.

**Empty panels?** — make sure Claude Code has been used on this machine (`~/.claude/projects` contains `.jsonl` files)

**Intel Macs?** — releases are arm64; build from source (`build.sh` compiles for the host architecture)

## 🙏 Credits

- UI inspired by the community's MyCodex usage tool
- Icon is a hand-made recreation of [Clawd](https://www.starkinsider.com/2025/10/clawd-ai-retro-mascot-command-line.html), Claude Code's pixel mascot
- Built with [Claude Code](https://claude.com/claude-code) 🤖

## 📄 License

[MIT](LICENSE) © CyberLinkPan
