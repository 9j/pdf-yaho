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

| Area | PDF Expert command | Pagecraft |
| --- | --- | --- |
| Reading | Single Page, Two Pages, Two Pages but First Single | ✅ Layout menu |
| Reading | Day, Night, Sepia | ✅ Theme menu |
| Reading | Zoom In/Out, 100%, Fit Width, Fit Page | ✅ |
| Reading | Thumbnails, Outline, Bookmarks panels | ✅ sidebar tabs |
| Reading | Find, Find Next/Previous | ✅ search with result list |
| Reading | Go to Page, First/Last/Next/Previous | ✅ Go menu |
| Annotate | Highlight, Underline, Strikeout | ✅ |
| Annotate | Pen, Eraser | ✅ |
| Annotate | Text, Note | ✅ double-click to edit |
| Annotate | Rectangle, Oval, Line, Arrow | ✅ |
| Annotate | Signature | ✅ drawn, stored on this Mac |
| Annotate | Annotation Summary, Export Annotation Summary | ✅ Markdown |
| Annotate | Remove All Annotations | ✅ |
| Annotate | Move annotations | ✅ drag with Select tool |
| Annotate | Stamp, Align/Rotate Annotation | ⏳ |
| Redact | Redact | ✅ mark areas, then Apply flattens those pages |
| Redact | Find and Redact | ⏳ |
| Pages | Rotate, Insert Blank Page, Delete, Reorder | ✅ thumbnails support drag |
| Pages | Insert From File, Extract | ✅ |
| Pages | Merge Files | ✅ |
| Pages | Add/Remove Page Numbers | ✅ |
| Pages | Crop, Split Pages, Page Labels, Bates, Header & Footer | ⏳ |
| Forms | Fill forms | ✅ AcroForm through PDFKit |
| Forms | XFA forms, Clear Form | ❌ / ⏳ |
| File | Save, Save As, Open Recent, tabs | ✅ standard macOS documents |
| File | Save as Flattened, Reduce File Size, Set Password | ✅ |
| File | Export to Text, Markdown, Images | ✅ |
| File | Export to Word, Excel, PowerPoint, HTML, RTF | ⏳ |
| File | New from Images | ✅ |
| File | Properties | ✅ title, author, subject, keywords |
| Edit PDF | Edit existing text and images | ❌ out of scope for PDFKit |
| Scan | Recognize Text (OCR), Enhance Scan | ⏳ planned with Vision |
| Compare | Split View, Sync Scroll | ⏳ |
| AI | Copilot, Chat, Summarize, Translate | ❌ not planned. Cloud AI does not fit a free offline app. |

✅ done · ⏳ planned · ❌ not planned
