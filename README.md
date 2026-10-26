# Pagecraft

A free, open-source PDF reader and editor for macOS, built on Apple PDFKit.
No account, no subscription, no telemetry.

Pagecraft covers the everyday features of commercial PDF editors such as PDF Expert:
reading, annotating, signing, redacting, filling forms and rearranging pages.
[docs/feature-parity.md](docs/feature-parity.md) lists what is done and what is planned.

## Using it

The toolbar holds the **toolsets**. Each one shows only the tools for one task, in a
floating bar at the top of the page:

| Toolset | Tools |
| --- | --- |
| Read | No tools. Select text for a Highlight / Underline / Strike / Copy menu. |
| Edit | The page's own text and images: retype, restyle, move, resize, replace, add, delete |
| Annotate | Highlight, underline, squiggly, strikeout, text, notes, callouts, stamps, images, links |
| Draw | Pen, marker, rectangles, ovals, lines, arrows, polygons, clouds |
| Fill & Sign | Text, checkmarks, crosses, dates, signatures and initials, stamps, form fields |
| Measure | Distance, perimeter and area at a scale you set |
| Redact | Black-box or white-out marks, Find and Redact, Apply |
| Scan | OCR, Enhance, clear margins, crop, page size, split book spreads |
| Pages | Large thumbnails. Select, drag to reorder, rotate, insert, copy/paste, extract, delete. |

Hide toolsets you never use with the **…** button. **Style** sets colour, size, opacity,
fill, line style and text formatting, for the active tool or the selected annotation. Click
an annotation to move it, resize it, change it or delete it. Hold ⇧ to keep lines straight
and shapes square. The **Display** button sets the page layout and theme, and opens a
second document in split view.

| Key | Tool | Key | Tool |
| --- | --- | --- | --- |
| V | Select | T | Text |
| H | Highlight | N | Note |
| U | Underline | R / O / L / A | Rectangle / Oval / Line / Arrow |
| K | Strikeout | G | Signature |
| P / M | Pen / Marker | X | Redact |
| E | Eraser | C / S | Crop / Snapshot |
| ⌘1 … ⌘9 | Toolsets | ⌘D | Bookmark page |
| ⌫ | Delete selection | Arrow keys | Nudge selection (⇧ for 10 pt) |

## Features

- **Home**: recent and favourite documents, and a Tools page that opens a file straight
  into a task such as compressing or signing it.
- **Read**: continuous, single, two-page and book layouts. Day, night and sepia themes.
  Thumbnails, bookmarks, an editable outline, and an annotation list with filters.
  Search with match-case, whole-word and history. Back/forward history.
- **Edit PDF**: click a paragraph to retype it in place, in its own font and width, in any
  language. Move text and images, resize or replace images, add new text and images, and
  change font, size and colour. Every edit is one undo step.
- **Compare**: two PDFs side by side or stacked, with scroll and zoom kept in sync.
- **Annotate**: highlight, underline, strikeout, pen, marker, text, notes, rectangles, ovals,
  lines, arrows, polygons, stamps, images and links. Set colour, opacity, thickness, fill and
  dashed lines. Copy, paste, duplicate and reorder annotations, with full undo.
- **Fill & sign**: fill forms and create form fields. Keep several signatures and initials,
  drawn, typed or imported from an image. Add checkmarks, crosses and dates.
- **Measure**: distance, perimeter and area, at a drawing scale you set.
- **Redact**: mark areas or every match of a search, as black boxes or white-out. Applying
  them flattens the marked pages, so the text underneath is actually removed.
- **Pages**: reorder, rotate, insert (blank, file, images, clipboard), duplicate, delete,
  crop, trim margins, resize, extract, split and merge. Add page numbers, headers, footers
  and Bates numbers. Edit page labels (i, ii … then 1, 2 …).
- **Save and share**: Save As Flattened. Share or mail a copy, as is or flattened. Reduce
  file size with four quality levels. Protect the document with a password. Recognise text
  in scans (OCR, on device).
- **Convert**: export to Word, Excel (tables become sheets), PowerPoint (a slide per page with
  editable text), RTF, HTML, text, Markdown, PNG/JPEG/TIFF or XFDF. Turn Word,
  RTF, HTML, Markdown, text and image files into PDF.

## Requirements

macOS 14 or later. Building needs Xcode 16 or the Swift 6 toolchain.

## Build

```sh
scripts/fetch-pdfium.sh         # once: pinned PDFium for Edit mode (build-app.sh runs it too)
scripts/build-app.sh            # universal release build → build/Pagecraft.app
ARCHS=arm64 scripts/build-app.sh debug
open build/Pagecraft.app
swift test                      # unit tests for PagecraftCore
```

Editing page content uses [PDFium](https://pdfium.googlesource.com/pdfium/) (BSD-3/Apache-2.0),
from the prebuilt [pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) release pinned
in `scripts/fetch-pdfium.sh`. It is bundled in `Contents/Frameworks` with its licences in
`Contents/Resources/Licenses/PDFium`. Without `Vendor/pdfium` the package still builds, with
Edit mode turned off.

The app is ad-hoc signed. The first time you open a copy built on another Mac,
right-click it and choose **Open**.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/PagecraftCore` | UI-free document operations: page edits, annotation factories, export, signatures. Unit tested. |
| `Sources/Pagecraft` | SwiftUI app: document window, PDF view and tools, sidebar, menus. |
| `Tests/PagecraftCoreTests` | XCTest suite for the core. |
| `Sources/CPDFium` | Module map for the vendored PDFium headers. |
| `scripts/build-app.sh` | Builds the `.app` bundle. |
| `scripts/fetch-pdfium.sh` | Downloads and checks the pinned PDFium into `Vendor/pdfium`. |
| `scripts/make-icon.swift` | Draws the app icon (`Resources/AppIcon.icns` is built from it). |

## Clean-room note

Pagecraft is not affiliated with Readdle or PDF Expert. The reference app was examined
only to list its features (see [docs/feature-parity.md](docs/feature-parity.md)). No
code, assets or text from it are included.

## License

MIT. See [LICENSE](LICENSE).
