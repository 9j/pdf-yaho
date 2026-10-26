# Feature parity with PDF Expert

Pagecraft is a clean-room reimplementation. It contains no code, artwork, strings or
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

No runtime tracing or decompilation was needed. The menu titles and plist answer what the
app offers. How Pagecraft implements each feature was decided independently.

## Status

The second pass went through all 1,700 English UI strings in the bundle's
`Localizable.strings`, not only the menu titles. That found tools that are not in the menus.

| Area | PDF Expert feature | Pagecraft |
| --- | --- | --- |
| Reading | Single, Two Pages, Two Pages with cover, continuous | ✅ |
| Reading | Day, Night, Sepia themes | ✅ |
| Reading | Zoom, Fit Width/Page, Go to Page, Back/Forward | ✅ |
| Reading | Thumbnails, Outline/Bookmarks, Annotations panel | ✅ |
| Reading | Find, Match Case, Whole Words | ✅ |
| Reading | Split View / Compare PDFs, Sync Scroll and Zoom, Swap Sides | ✅ |
| Annotate | Highlight, Underline, Strikeout | ✅ |
| Annotate | Pen, Marker, Eraser | ✅ |
| Annotate | Text, Note, Callout | ✅ text and note · ⏳ callout |
| Annotate | Rectangle, Oval, Line, Arrow, Double Arrow, Polygon, Polyline | ✅ |
| Annotate | Colour, Opacity, Thickness, Fill, Dashed/Dotted lines | ✅ |
| Annotate | Text Stamps, Image Stamps, custom stamps | ✅ |
| Annotate | Image tool, Link to Page / Link to Web | ✅ |
| Annotate | Copy, Cut, Paste, Duplicate, Bring to Front, Send to Back | ✅ |
| Annotate | Author name on annotations | ✅ Settings |
| Annotate | Export Annotations (XFDF), Annotation Summary | ✅ |
| Annotate | Squiggly, Sound, Attachment | ❌ PDFKit cannot create these |
| Fill & Sign | Signatures and initials: draw, type, image; several saved | ✅ |
| Fill & Sign | Checkmark, Cross, Date | ✅ |
| Forms | Fill forms, Clear Form | ✅ |
| Forms | Create Text Field, Checkbox, Radio Button, Drop-down | ✅ |
| Forms | XFA forms, Form Assistant, Submit to URL | ❌ |
| Measure | Distance, Perimeter, Area, Scale | ✅ |
| Redact | Redact area, Black Box or White Out, Apply | ✅ |
| Redact | Find and Redact | ✅ |
| Pages | Insert blank / from file / images / clipboard, Duplicate, Delete, Reorder | ✅ |
| Pages | Rotate, Reverse | ✅ |
| Pages | Crop (page or all), Clear Margins, Reset Crop | ✅ |
| Pages | Page Size / Resize with scale to fit | ✅ |
| Pages | Extract, Split (every N, odd/even, ranges), Merge | ✅ |
| Pages | Page Numbers, Header and Footer, Bates Numbering | ✅ |
| Pages | Page Labels (i, ii, iii…) | ❌ PDFKit has no API for writing page labels |
| File | Save, Save As, Revert, Open Recent, tabs, Welcome window | ✅ |
| File | Save As Flattened, Export as Flattened | ✅ |
| File | Share / Mail as Document or as Flattened | ✅ |
| File | Reduce File Size (Lossless, High, Medium, Low) | ✅ |
| File | Set, Change and Remove Password on the document | ✅ |
| File | Export to Word, RTF, HTML, Text, Markdown, PNG/JPEG/TIFF | ✅ |
| File | Export to Excel, PowerPoint | ❌ |
| File | Convert Word, ODT, RTF, HTML, Markdown, text and images to PDF | ✅ |
| File | Properties | ✅ |
| Scan | Recognize Text (OCR) | ✅ on-device |
| Scan | Enhance Scan, Remove Distortion | ⏳ |
| Edit PDF | Edit existing text and images in the page content | ❌ PDFKit cannot edit page content |
| AI | Copilot, Chat, Summarize, Translate | ❌ not planned. Cloud AI does not fit a free offline app. |

✅ done · ⏳ planned · ❌ not possible with PDFKit or not planned
