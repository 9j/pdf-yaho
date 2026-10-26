# Pagecraft

A free, open-source PDF reader and editor for macOS, built on Apple PDFKit.
No account, no subscription, no telemetry.

Pagecraft covers the everyday features of commercial PDF editors such as PDF Expert:
reading, annotating, signing, redacting, filling forms and rearranging pages.
[docs/feature-parity.md](docs/feature-parity.md) lists what is done and what is planned.

## Using it

The toolbar switches between three modes:

- **Read** is a clean reading view. Select text and a small menu offers Highlight, Underline, Strike and Copy.
- **Markup** shows a floating tool palette. Each tool remembers its own colour and size, which you set
  under **Style**. Click any annotation to select it. You can then drag it, resize it from a corner,
  change its colour, duplicate it or delete it. Text boxes and notes are typed directly on the page.
- **Pages** shows every page as a large thumbnail. Click, ⌘-click or ⇧-click to select pages, and drag
  them to reorder. The bar at the bottom rotates, inserts, extracts and deletes.

A capsule at the bottom of the page handles page navigation and zoom.

| Key | Tool | Key | Tool |
| --- | --- | --- | --- |
| V | Select | T | Text |
| H | Highlight | N | Note |
| U | Underline | R / O / L / A | Rectangle / Oval / Line / Arrow |
| K | Strikeout | G | Signature |
| P | Pen | X | Redact |
| E | Eraser | ⌫ | Delete selected annotation |
| ⌘1 / ⌘2 / ⌘3 | Read / Markup / Pages | Arrow keys | Nudge selection (⇧ for 10 pt) |

## Features

- **Read**: continuous, single, two-page and book layouts. Day, night and sepia themes.
  Thumbnails, outline, annotation list and full-text search.
- **Annotate**: highlight, underline, strikeout, pen, text, notes, rectangles, ovals,
  lines and arrows. Annotations can be moved, edited and erased, with full undo.
- **Sign**: draw a signature once, then place it on any page.
- **Redact**: mark areas, then apply. Marked pages are flattened into images, so the
  covered text is actually removed and not just hidden.
- **Organise pages**: drag to reorder, rotate, insert blank pages, insert pages from
  another PDF, extract, delete, merge files, add page numbers and bookmarks.
- **Forms**: fill AcroForm fields.
- **Save and export**: flattened copies, smaller copies, password-protected copies.
  Export to plain text, Markdown, PNG or an annotation summary. Build a PDF from images.

## Requirements

macOS 14 or later. Building needs Xcode 16 or the Swift 6 toolchain.

## Build

```sh
scripts/build-app.sh            # universal release build → build/Pagecraft.app
ARCHS=arm64 scripts/build-app.sh debug
open build/Pagecraft.app
swift test                      # unit tests for PagecraftCore
```

The app is ad-hoc signed. The first time you open a copy built on another Mac,
right-click it and choose **Open**.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/PagecraftCore` | UI-free document operations: page edits, annotation factories, export, signatures. Unit tested. |
| `Sources/Pagecraft` | SwiftUI app: document window, PDF view and tools, sidebar, menus. |
| `Tests/PagecraftCoreTests` | XCTest suite for the core. |
| `scripts/build-app.sh` | Builds the `.app` bundle. |
| `scripts/make-icon.swift` | Draws the app icon (`Resources/AppIcon.icns` is built from it). |

## Clean-room note

Pagecraft is not affiliated with Readdle or PDF Expert. The reference app was examined
only to list its features (see [docs/feature-parity.md](docs/feature-parity.md)). No
code, assets or text from it are included.

## License

MIT. See [LICENSE](LICENSE).
