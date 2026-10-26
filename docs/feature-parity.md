# Feature parity with PDF Expert

PDF Yaho is a clean-room reimplementation. It contains no code, artwork, strings or
resources from PDF Expert. The reference app was examined to build a list of features,
then each feature was written from scratch on Apple's PDFKit.

## How the feature list was made

Reference: PDF Expert 3.13.4 (build 1177), `com.readdle.PDFExpert-Mac`, universal
arm64/x86_64 Mach-O, SHA-256 `d48539f11c99da7ed5ac8dffac27628b8344c98a56e0153ed75e63c9148ede67`.

- **Bundle metadata** was read with REA (`rea-agents`), `inspect_plist`, Evidence
  `ev_3b4993013dc58ef4966695aad1461e3d1bc5ee798fce871bdeb27f0e4b1feed4`. That record shows:
  - PDF is the only editable document type. Images and about 100 office, iWork, ePub and
    camera RAW types are opened through conversion.
  - The app ships with proprietary frameworks for its PDF engine, XFA forms, OCR,
    translation and AI. Other bundled components handle licensing (Paddle), attribution
    (AppsFlyer), crash reporting and remote config (Firebase), and updates (Sparkle).
- **Menu commands** came from the bundle's `en.lproj/MainMenu.strings`. Only the titles
  were used, as a list of features.

- **Asset catalogs** (REA `inspect_asset_catalog`, Evidence
  `ev_6f56e6ed8ca131850b2251ea34604ee6ca65d866821fc92cceffff3307157c33`; 2,719 records in 11
  catalogs). Only the asset *names* were read. They show the toolbar's toolsets ("ribbons"),
  tool families (squiggly, callout, cloud shapes, line endings, border types), scan tools,
  sidebar panels and the merge dialog.
- **HomeTab design notes** shipped inside the bundle (`HomeTab.framework/.../ARCHITECTURE.md`)
  describe the Home tab's pages (Home, Recents, Favorites, Tools) and behaviour.

No runtime tracing or decompilation was needed. The menu titles and plist answer what the
app offers. How PDF Yaho implements each feature was decided independently.

## Status

The second pass went through all 1,700 English UI strings in the bundle's
`Localizable.strings`, not only the menu titles. That found tools that are not in the menus.

| Area | PDF Expert feature | PDF Yaho |
| --- | --- | --- |
| Reading | Single, Two Pages, Two Pages with cover, continuous | ✅ |
| Reading | Day, Night, Sepia themes | ✅ |
| Reading | Zoom, Fit Width/Page, Go to Page, Back/Forward | ✅ |
| Reading | Thumbnails, Outline/Bookmarks, Annotations panel | ✅ |
| Reading | Find, Match Case, Whole Words | ✅ |
| Reading | Split View in the window, Compare PDFs, Sync Scroll and Zoom, Swap Sides | ✅ |
| Reading | Bookmarks (personal) with page-corner ribbon, editable Outline | ✅ |
| Reading | Back to p. N after jumps, search history, auto-hiding page indicator | ✅ |
| Interface | Toolsets in the toolbar (Annotate, Draw, Fill & Sign, Measure, Redact, Scan), hide unused | ✅ |
| Interface | Home: Tools for You, Recents, Favorites, Tools page, drop to open | ✅ |
| Interface | Documents in tabs, Settings (tabs/windows, defaults, page indicator, author) | ✅ |
| Annotate | Highlight, Underline, Strikeout | ✅ |
| Annotate | Pen, Marker, Eraser | ✅ |
| Annotate | Text (font, bold/italic, alignment, background), Note, Callout | ✅ |
| Annotate | Squiggly underline | ✅ custom-drawn (PDFKit saves but never draws it) |
| Annotate | Cloud rectangle and cloud polygon (redline) | ✅ |
| Annotate | Border types (solid, dashed ×3, dotted, dash-dotted), line endings | ✅ |
| Annotate | Shift to constrain lines and shapes | ✅ |
| Annotate | Image annotation: replace, save | ✅ |
| Annotate | Rectangle, Oval, Line, Arrow, Double Arrow, Polygon, Polyline | ✅ |
| Annotate | Colour, Opacity, Thickness, Fill, Dashed/Dotted lines | ✅ |
| Annotate | Text Stamps, Image Stamps, custom stamps | ✅ |
| Annotate | Image tool, Link to Page / Link to Web | ✅ |
| Annotate | Copy, Cut, Paste, Duplicate, Bring to Front, Send to Back | ✅ |
| Annotate | Author name on annotations | ✅ Settings |
| Annotate | Export Annotations (XFDF), Annotation Summary | ✅ |
| Annotate | Sound notes, file attachments, hatch fill patterns, variable-width pen | ❌ |
| Fill & Sign | Signatures and initials: draw, type, image; several saved | ✅ |
| Fill & Sign | Checkmark, Cross, Date | ✅ |
| Forms | Fill forms, Clear Form | ✅ |
| Forms | Create Text Field, Checkbox, Radio Button, Drop-down | ✅ |
| Forms | XFA forms, Form Assistant, Submit to URL | ❌ XFA is deprecated in PDF 2.0; static XFA files usually carry AcroForm fields, which work |
| Measure | Distance, Perimeter, Area, Scale | ✅ |
| Redact | Redact area, Black Box or White Out, Apply | ✅ |
| Redact | Find and Redact | ✅ |
| Pages | Insert blank / from file / images / clipboard, Duplicate, Delete, Reorder | ✅ |
| Pages | Copy, Cut and Paste pages | ✅ |
| Pages | Rotate, Reverse | ✅ |
| Pages | Crop (page or all), Clear Margins, Reset Crop | ✅ |
| Pages | Page Size / Resize with scale to fit | ✅ |
| Pages | Extract, Split (every N, odd/even, ranges), Merge | ✅ |
| Pages | Page Numbers, Header and Footer, Bates Numbering | ✅ |
| Pages | Page Labels (i, ii, iii…), shown in thumbnails and the page field | ✅ written as an incremental update, since PDFKit drops them |
| File | Save, Save As, Revert, Open Recent, tabs, Welcome window | ✅ |
| File | Save As Flattened, Export as Flattened | ✅ |
| File | Share / Mail as Document or as Flattened | ✅ |
| File | Reduce File Size (Lossless, High, Medium, Low) | ✅ |
| File | Set, Change and Remove Password on the document | ✅ |
| File | Export to Word, RTF, HTML, Text, Markdown, PNG/JPEG/TIFF | ✅ |
| File | Export to Excel (tables), PowerPoint (editable text over page art) | ✅ |
| File | Convert Word, ODT, RTF, HTML, Markdown, text and images to PDF | ✅ |
| File | Merge Files window (drop, reorder, unlock, convert any type) | ✅ |
| File | Properties | ✅ |
| Scan | Recognize Text (OCR) | ✅ on-device |
| Scan | Enhance Scan (black & white, grayscale, colour), Split book spreads | ✅ |
| Scan | Remove perspective distortion, camera scanning | ❌ |
| Edit PDF | Edit, move, restyle and delete existing text; add text | ✅ with PDFium |
| Edit PDF | Move, resize, replace, save and delete images; add images | ✅ with PDFium |
| AI | Copilot, Chat, Summarize, Translate | ❌ not planned. Cloud AI does not fit a free offline app. |

✅ done · ⏳ planned · ❌ not possible or not planned
