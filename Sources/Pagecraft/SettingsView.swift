import PagecraftCore
import SwiftUI

/// Pagecraft ▸ Settings: General, Viewer and Annotations tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ViewerSettings().tabItem { Label("Viewer", systemImage: "doc.richtext") }
            AnnotationSettings().tabItem { Label("Annotations", systemImage: "highlighter") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @AppStorage("openInTabs") private var openInTabs = true
    @AppStorage("showHomeWhenIdle") private var showHome = true
    @State private var isDefault = false

    var body: some View {
        Form {
            Picker("Open documents in", selection: $openInTabs) {
                Text("Tabs").tag(true)
                Text("Separate windows").tag(false)
            }
            Toggle("Show Home when no documents are open", isOn: $showHome)
            LabeledContent("Default PDF app") {
                if isDefault {
                    Label("Pagecraft is the default", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Make Pagecraft the Default") {
                        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .pdf) { _ in
                            DispatchQueue.main.async { refresh() }
                        }
                    }
                }
            }
            LabeledContent("Recent documents") {
                Button("Clear Recents") { NSDocumentController.shared.clearRecentDocuments(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 230)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isDefault = NSWorkspace.shared.urlForApplication(toOpen: .pdf)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

private struct ViewerSettings: View {
    @AppStorage("defaultLayout") private var layout = PageLayout.continuous.rawValue
    @AppStorage("defaultTheme") private var theme = ReadingTheme.day.rawValue
    @AppStorage("pageIndicator") private var indicator = Preferences.PageIndicator.automatic.rawValue
    @AppStorage("showSidebar") private var showSidebar = true

    var body: some View {
        Form {
            Picker("Page layout", selection: $layout) {
                ForEach(PageLayout.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Reading theme", selection: $theme) {
                ForEach(ReadingTheme.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Page number indicator", selection: $indicator) {
                ForEach(Preferences.PageIndicator.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Toggle("Show the sidebar when opening documents", isOn: $showSidebar)
            Text("Layout and theme apply to documents you open next.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 230)
    }
}

private struct AnnotationSettings: View {
    @AppStorage("authorName") private var author = ""

    var body: some View {
        Form {
            TextField("Author name", text: $author, prompt: Text(NSFullUserName()))
            Text("Shown as the author of your highlights, notes and stamps in other PDF apps.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Tips") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold ⇧ while drawing lines and shapes to keep them straight or square.")
                    Text("Press a tool’s letter (H, U, P, T…) to switch tools.")
                    Text("Esc returns to the Select tool.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 230)
    }
}
