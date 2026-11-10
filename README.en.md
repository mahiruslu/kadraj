<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Kadraj">
</p>

<h1 align="center">Kadraj</h1>

<p align="center">
  <b>An open-source screenshot tool for macOS.</b><br>
  Select, draw on it, copy — all in one flow.
</p>

<p align="center">
  <a href="https://github.com/mahiruslu/kadraj/releases/latest"><img src="https://img.shields.io/github/v/release/mahiruslu/kadraj?color=6d5df6" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple-notarized-34c759" alt="Notarized">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/mahiruslu/kadraj?color=blue" alt="MIT"></a>
</p>

<p align="center">
  <a href="README.md">Türkçe</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="The toolbar right under the selection: box, arrow, numbered steps and pixelate" width="860">
</p>

> The interface is in Turkish for now; button names below are given with their meaning.

## Install

One line, no admin password:

```bash
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash
```

<details>
<summary>A specific release or the development build</summary>

```bash
# A specific release (with or without the leading v)
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- 0.1.1

# Nightly build of main
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- main
```
</details>

macOS 14 Sonoma or later · Apple Silicon and Intel · signed and notarized by Apple, no Gatekeeper warning.

## What it does

- ✏️ **Annotate in place** — The moment you select an area, a toolbar opens under it: arrow, box, ellipse, pen, highlighter, text, numbered steps, blur, pixelate. Click a window without dragging to select it instead. The selection stays resizable while you annotate.
- 📜 **Scrolling capture** — Stitches long pages and chats into one image; sticky headers and footers don't repeat.
- 🔤 **OCR and QR** — Reads text in the selection offline (Turkish included) and decodes QR codes.
- 🎬 **Screen recording and GIF** — Records an area or the whole screen as MP4, converts it to GIF in one click.
- 📌 **Pin to screen** — Keeps an image floating above everything.
- 🎨 **Color picker and ruler** — Copies a pixel's color as HEX/RGB/HSL, measures on screen.
- 🔒 **Private** — Everything runs on your Mac; Kadraj never goes online unless you ask.

<table>
  <tr>
    <td width="50%"><img src="docs/images/ocr.png" alt="OCR result: text copied"></td>
    <td width="50%"><img src="docs/images/scroll.png" alt="Scrolling capture with live preview"></td>
  </tr>
  <tr>
    <td align="center"><sub>Text in the selection, on your clipboard</sub></td>
    <td align="center"><sub>Scroll, Kadraj stitches</sub></td>
  </tr>
</table>

## Usage

Kadraj lives in the menu bar (viewfinder icon). Every shortcut can be changed in **Settings**. Don't want the icon? Hide it with **Settings → Genel → "Menü çubuğunda göster"** (show in menu bar); shortcuts keep working, and opening Kadraj again from Applications or Spotlight brings the settings back.

| Shortcut | Action |
|---|---|
| `⌥⇧A` | Select an area (or click a window) and annotate in place |
| `⌥⇧W` | Capture a window |
| `⌥⇧F` | Full screen |
| `⌥⇧S` | Scrolling capture (press `⌥⇧S` again or **Bitti** / Done to finish) |
| `⌥⇧R` | Start / stop screen recording |
| `⌥⇧O` | Recognize text (OCR) |
| `⌥⇧Q` | Read a QR code |
| `⌥⇧C` | Pick a color |
| `⌥⇧M` | Ruler |

### After selecting

When you release the selection, a two-row toolbar opens under it:

- **Top row:** tools, colors, width (S/M/L), undo / redo
- **Bottom row:** **Metin** (OCR), **QR**, **Pinle** (pin), **Editör** (editor), **Kaydet** (save, `⌘S`), **Kopyala** (copy, `⌘C`), **Bitti** (done, `Return`)

Resize the selection with its corner and edge handles; with no annotation selected, arrow keys move it and `⌥`+arrows resize it. `Esc` cancels.

<details>
<summary>Tool shortcuts</summary>

| Key | Tool | Key | Tool |
|---|---|---|---|
| `V` | Select / move (`⌫` deletes) | `T` | Text |
| `A` | Arrow | `N` | Numbered step |
| `L` | Line | `B` | Blur |
| `R` | Rectangle | `M` | Pixelate |
| `O` | Ellipse | `C` | Crop (editor only) |
| `P` | Pen | `H` | Highlighter |

`⇧` snaps lines/arrows to 45° and rectangles/ellipses to squares. Changing color or width also restyles the selected annotation.
</details>

Prefer instant captures? **Settings → Genel → "Fareyi bırakınca hemen yakala"** (capture on release) saves/copies as soon as you release, with a **Quick Access** thumbnail in the bottom-right corner.

### Automation

From Raycast, Alfred or Shortcuts:

```bash
open "kadraj://capture/area"     # window, fullscreen, scroll, record, text, qr, color, ruler
open "kadraj://settings"
open "kadraj://check-updates"
```

## Permissions

Kadraj only needs **Screen Recording**. On first launch it guides you: enable Kadraj under *System Settings → Privacy & Security → Screen Recording*, then relaunch it.

macOS 15 and later occasionally show *"Kadraj is requesting to bypass the system private window picker…"* — a system prompt every screen-capturing tool gets; choose **Allow**.

If your organization blocks this permission via MDM, IT can let standard users grant it themselves with the profile in [docs/MDM.md](docs/MDM.md).

> Turkish OCR needs a macOS version whose Vision includes the Turkish model; older versions use the other languages.

## Updating and uninstalling

Menu → **Güncellemeleri Kontrol Et…** (Check for Updates): a new version is downloaded, its signature verified and Kadraj updated in place (no admin rights). Re-running the install command also updates. **Settings → Girişte başlat** launches Kadraj at login.

To uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/uninstall.sh | bash
```

## Development

Swift 6 and SwiftPM; there is no `.xcodeproj`. Open the code in Xcode with `xed .`, run it with `scripts/dev.sh` (builds, bundles a `.app`, signs and relaunches).

```bash
swift test                        # unit tests
scripts/dev.sh                    # fast dev loop (dist-dev/Kadraj.app)
scripts/bundle.sh                 # dist/Kadraj.app (universal)
/bin/bash Tests/install_test.sh   # installer tests
```

> If `swift build` fails with a manifest link error under Command Line Tools, use Xcode's toolchain: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Releasing: pushing a `v*` tag makes GitHub Actions build, sign, notarize and publish the release (tags containing `-` become prereleases). The required secrets are listed in the [Turkish README](README.md#geliştirme).

## License

[MIT](LICENSE) © 2026 Mahir Uslu
