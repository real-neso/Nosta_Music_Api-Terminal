[README.md](https://github.com/user-attachments/files/31565731/README.md)
# Nosta Music CLI

> Terminal-based music management tool for the Nosta platform.
> Upload, stream, edit, and organize your music library directly from the command line.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Termux%20%7C%20macOS-lightgrey.svg)]()
[![Dependencies](https://img.shields.io/badge/deps-curl%2C%20jq%2C%20mpv-green.svg)]()

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [File Structure](#file-structure)
- [Two Flavors](#two-flavors)
- [Installation](#installation)
- [Usage](#usage)
- [Requirements](#requirements)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Screenshots](#screenshots)
- [Uninstallation](#uninstallation)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

**Nosta Music CLI** is the official terminal interface for managing music assets on the Nosta platform. It connects to `nosta-server.onrender.com` and provides a complete workflow for:

- Uploading single tracks or entire folders
- Streaming music via `mpv`
- Editing metadata (title, artist, visibility)
- Batch-updating artists from audio file tags
- Managing favorites and viewing statistics
- Deleting tracks (single or bulk)

Built for **Kitty**, **Alacritty**, **GNOME Terminal**, **Termux**, and any standard POSIX terminal.

---

## Features

| Feature | Description |
|---------|-------------|
| **Upload** | Single file or bulk folder upload with auto metadata extraction |
| **Stream** | Play any track instantly via `mpv` with Bearer token auth |
| **Search** | Full-text search across your library |
| **Edit** | Update metadata or replace audio file while keeping the same ID |
| **Batch Artist Update** | Scan "Unknown Artist" tracks and fix them from file tags or local folder |
| **Favorites** | View and play your starred tracks |
| **Statistics** | Total songs, pages, user role info |
| **Kitty Graphics** | Inline cover-art and avatar display (falls back gracefully) |
| **Auto Auth** | JWT token persistence in `~/.nosta_token` |
| **FFmpeg Integration** | Automatic title/artist/cover extraction from audio files |

---

## File Structure

```
Nosta-Api/music-api/
├── nosta.sh                  # Fancy UI version (emoji + decorative borders)
├── nosta_clean.sh            # Basic UI version (minimal, no emoji)
├── install_nosta_music.sh    # Interactive installer & uninstaller
└── README.md                 # This file
```

### File Descriptions

#### `nosta.sh` — Fancy UI
- Rich emoji icons (🎵 📊 🔍 ✏️ 🗑️ ⭐)
- Decorative box-drawing borders for tables
- Colorful headers and progress indicators
- Best for: modern terminals with Unicode & 256-color support

#### `nosta_clean.sh` — Basic UI
- Zero emoji, zero decorative borders
- Plain text output with minimal ANSI colors
- Fast, universal, works everywhere
- Best for: Termux, old terminals, SSH sessions, or users who prefer simplicity

#### `install_nosta_music.sh` — Installer
- Dependency checker (`curl`, `jq`, `mpv`, `ffmpeg`)
- Auto-installer for missing packages (supports `pkg`, `pacman`, `apt`, `dnf`, `apk`)
- UI selector (Fancy vs Basic)
- Optional PATH modification
- Built-in uninstaller (`--uninstall` flag)
- ANSI logo with fallback for narrow terminals

---

## Two Flavors

| | Fancy (`nosta.sh`) | Basic (`nosta_clean.sh`) |
|---|---|---|
| **Emoji** | Yes | No |
| **Borders** | Box-drawing chars | None |
| **Colors** | Rich 256-color | Minimal ANSI |
| **Speed** | Slightly slower | Faster |
| **Termux** | Works but may clip | Perfect |
| **Old SSH** | May break layout | Always clean |

Both versions share **100% identical functionality**. Only the visual style differs.

---

## Installation

### One-liner (Recommended)

```bash
bash <(curl -sL https://raw.githubusercontent.com/YOUR_USER/nosta/main/install_nosta_music.sh)
```

### Termux

```bash
pkg update && pkg install -y curl
bash <(curl -sL https://raw.githubusercontent.com/YOUR_USER/nosta/main/install_nosta_music.sh)
```

### Manual

```bash
# 1. Download your preferred version
curl -sL https://raw.githubusercontent.com/YOUR_USER/nosta/main/nosta_clean.sh -o nosta-music

# 2. Make executable
chmod +x nosta-music

# 3. Move to PATH
mv nosta-music ~/.local/bin/
```

### What the installer does

1. Detects your package manager (`pkg`, `pacman`, `apt`, `dnf`, `apk`)
2. Checks for `curl`, `jq`, `mpv` (installs if missing)
3. Checks for `ffmpeg` (optional but recommended)
4. Asks you to choose **Fancy** or **Basic** UI
5. Downloads the selected version to `~/.local/bin/nosta-music`
6. Optionally adds `~/.local/bin` to your `PATH`
7. Offers to launch immediately

---

## Usage

### Launch

```bash
nosta-music
```

Or directly:
```bash
~/.local/bin/nosta-music
```

### Main Menu

```
MAIN MENU
  1) List All Songs
  2) Search Songs
  3) Upload Song(s)
  4) Edit Song
  5) Delete Song
  6) Delete Multiple Songs
  7) View Favorites
  8) User Profile
  9) Statistics
  10) Now Playing
  11) Update Artists (from server)
  12) Update Artists (from local folder)
  0) Logout & Exit
```

### First Run

On first launch you will be prompted to log in:
```
Email: your@email.com
Password: ********
```

Your JWT token is saved to `~/.nosta_token` for subsequent runs.

### Uploading Music

**Single file:**
```
→ 3) Upload Song(s)
→ 1) Upload single file
→ Enter file path: /sdcard/Music/song.mp3
→ Title: [auto-detected or custom]
→ Artist: [auto-detected or custom]
→ Public? (y/n): y
```

**Entire folder:**
```
→ 3) Upload Song(s)
→ 2) Upload all songs from folder
→ Enter folder path: /sdcard/Music/
→ Auto-detects metadata for each file
→ Uploads sequentially with progress report
```

### Streaming

```
→ 1) List All Songs
→ p) Play song
→ Enter song number: 3
→ mpv launches in background
```

Stop playback anytime from the main menu with option `0` (Logout & Exit) or by killing the `mpv` process.

### Batch Artist Fix

If you have tracks with "Unknown Artist", use:

- **Option 11** — Downloads each track, extracts real artist from audio tags via `ffprobe`, updates server
- **Option 12** — Scans a local folder for matching filenames, extracts artist from local files without re-downloading

---

## Requirements

### Required
| Package | Purpose |
|---------|---------|
| `curl` | HTTP requests to API |
| `jq` | JSON parsing |
| `mpv` | Audio playback |

### Optional
| Package | Purpose |
|---------|---------|
| `ffmpeg` / `ffprobe` | Metadata & cover-art extraction |
| `exiftool` | Fallback cover-art extraction |

### Install by Platform

**Termux:**
```bash
pkg install curl jq mpv ffmpeg
```

**Arch / Manjaro:**
```bash
sudo pacman -S curl jq mpv ffmpeg
```

**Debian / Ubuntu:**
```bash
sudo apt-get install curl jq mpv ffmpeg
```

**Fedora:**
```bash
sudo dnf install curl jq mpv ffmpeg
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `1-12`, `0` | Menu selection |
| `p` | Play song (from list/search/favorites) |
| `i` | Show cover art (from list/search) |
| `Enter` | Back to menu |
| `Ctrl+C` | Force quit |

---

## Screenshots

> *Screenshots vary by UI flavor. Fancy version shown below.*

**Login**
```
  LOGIN
  Email: user@example.com
  Password: ********
  [OK] Login successful
```

**Song List (Fancy)**
```
┌─────────────────────────────────────────┐
│ #  ID      TITLE              ARTIST    │
├─────────────────────────────────────────┤
│ 1  abc12  Summer Vibes       DJ Cool   │
│ 2  def34  Midnight Drive     The Band  │
└─────────────────────────────────────────┘
```

**Song List (Basic)**
```
  #  ID      TITLE              ARTIST
  1  abc12  Summer Vibes       DJ Cool
  2  def34  Midnight Drive     The Band
```

---

## Uninstallation

### Via Installer
```bash
bash install_nosta_music.sh --uninstall
# or
bash install_nosta_music.sh -u
```

Type `uninstall` to confirm. This removes:
- `~/.local/bin/nosta-music`
- `~/.nosta/` (config dir)
- `~/.nosta_token` & `~/.nosta_user`
- `/tmp/nosta_uploads`
- PATH entry from `~/.bashrc`

### Manual
```bash
rm -f ~/.local/bin/nosta-music
rm -rf ~/.nosta ~/.nosta_token ~/.nosta_user /tmp/nosta_uploads
sed -i '/\.local\/bin/d' ~/.bashrc
source ~/.bashrc
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `mpv: command not found` | Install `mpv` via your package manager |
| `jq: command not found` | Install `jq` via your package manager |
| Cover art not displaying | Install `ffmpeg` for automatic extraction |
| Login fails | Check credentials; token auto-refreshes on next run |
| Upload fails | Verify file path; check server status |
| Kitty images broken | Normal on non-Kitty terminals; falls back to URL |
| Termux: path not found | Run `termux-setup-storage` to access `/sdcard/` |

---

## API Reference

The CLI communicates with:
```
Base URL: https://nosta-server.onrender.com/api/v1
Auth:     Bearer JWT via ~/.nosta_token
Secret:   X-App-Secret header
```

Endpoints used:
- `POST /api/auth/login`
- `GET /api/v1/songs`
- `GET /api/v1/songs/search`
- `POST /api/v1/songs/upload`
- `PUT /api/v1/songs/{id}`
- `DELETE /api/v1/songs/{id}`
- `GET /api/v1/songs/{id}/stream`
- `GET /api/v1/songs/favorites`

---

## Contributing

This is part of the **Nosta** project. For the main platform (Instagram alternative), see the parent repository.

To contribute to the CLI:
1. Fork this repo
2. Edit `nosta.sh` or `nosta_clean.sh`
3. Test on both modern terminals and Termux
4. Submit a PR

---

## License

MIT License — see [LICENSE](../LICENSE) for details.

---

> Built with Bash, caffeine, and late-night coding sessions.
