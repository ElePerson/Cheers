import SwiftUI
import Charts

/// Workbench — the channel's file workspace with native, inert renderers.
///
/// The web workbench is file-centric: browse the tree, open a file, and it renders
/// through a bound *renderer* (a built-in lens or a sandboxed HTML plugin), falling
/// back to "Raw" when nothing is bound. iOS never executes HTML plugin bundles;
/// Markdown, table, kanban and chart are rendered with native SwiftUI views.
///
/// **`fs.ls` returns a FLAT, recursive list of full paths** — `draft/paper.md`, not a
/// `draft` directory containing `paper.md` — and in practice emits no `is_dir` rows at
/// all. So, exactly like the web `buildTree` (workbench/panels/FilePanel.tsx), the
/// folder hierarchy is *derived client-side*: a folder is any path prefix that has
/// children (or an explicit `is_dir` row, which materializes a possibly-empty folder).
/// One `fs.ls` at the root feeds the whole browser; drilling down costs no round trip.
///
/// Everything here is agent-authored and untrusted — like ViewBoards, it renders as
/// inert `Text`, never as markup and never as tappable links.
struct WorkbenchSheet: View {
    @Environment(AppModel.self) private var app
    let channelId: String

    /// Folder stack: [] is the workspace root, one segment appended per drill-down.
    @State private var stack: [String] = []
    @State private var openFile: TreeNode?
    @State private var root: [TreeNode] = []
    @State private var errorText: String?
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var templates: [WorkbenchTemplateRow] = []
    @State private var isApplyingTemplate = false
    @State private var lensBindings: [String: String] = [:]

    private var currentPath: String { stack.joined(separator: "/") }

    /// Children of the folder the user is currently in, walked down from the root.
    private var visible: [TreeNode] {
        var nodes = root
        for segment in stack {
            guard let next = nodes.first(where: { $0.isDir && $0.name == segment }) else { return [] }
            nodes = next.children
        }
        return nodes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let openFile {
                FileContentView(
                    channelId: channelId, node: openFile,
                    preferredLens: lensBindings[openFile.path]
                )
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if let errorText {
                ComingSoon(icon: "exclamationmark.triangle", text: errorText)
            } else if visible.isEmpty {
                ComingSoon(icon: "folder", text: "No files here yet.")
            } else {
                List(visible) { node in
                    Button {
                        if node.isDir { stack.append(node.name) } else { openFile = node }
                    } label: {
                        row(node)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.bgSurface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bgSurface)
        .task {
            async let files: Void = load()
            async let templateList: Void = loadTemplates()
            _ = await (files, templateList)
        }
    }

    private func row(_ node: TreeNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDir ? "folder.fill" : icon(for: node.name))
                .font(.system(size: 15))
                .foregroundStyle(node.isDir ? Theme.accent : Theme.textMuted)
                .frame(width: 22)
            Text(node.name)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if node.isDir {
                Text("\(node.children.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            } else {
                Text(size(node.sizeBytes))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .contentShape(Rectangle())
    }

    private func icon(for name: String) -> String {
        switch name.split(separator: ".").last.map(String.init)?.lowercased() {
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yaml", "yml", "toml", "xml": return "curlybraces"
        default: return "doc"
        }
    }

    private func size(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
    }

    /// `showSpinner: false` on a manual refresh — replacing the list with a full-frame
    /// ProgressView would make the tree flicker away under the user's finger; the header
    /// button shows the progress instead.
    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true } else { isRefreshing = true }
        defer { isRefreshing = false }
        do {
            // One recursive listing for the whole workspace — see the type doc.
            let raw = try await app.socket.request(
                resource: "fs.ls", params: ["channel_id": channelId, "path": ""])
            root = TreeNode.build(from: try raw.decode(as: FsListing.self).entries)
            errorText = nil
        } catch {
            errorText = (error as? ResourceError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private var header: some View {
        HStack(spacing: 8) {
            if openFile != nil || !stack.isEmpty {
                Button {
                    if openFile != nil { openFile = nil } else { stack.removeLast() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                Image(systemName: "sidebar.right").foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(openFile?.name ?? "Workbench")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Show where we are; the root shows the purpose instead of an empty path.
                Text(breadcrumb)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            // The tree is a snapshot — nothing pushes a bot's new file into an open
            // sheet. This is a BUTTON, not pull-to-refresh: inside a presentationDetents
            // sheet a downward pan is claimed by the sheet's own resize/dismiss gesture,
            // so `.refreshable` never fires (verified on device).
            if openFile == nil {
                Menu {
                    if templates.isEmpty {
                        Text("No templates installed")
                    } else {
                        ForEach(templates) { template in
                            Button(template.title) { Task { await apply(template.manifest) } }
                        }
                    }
                } label: {
                    if isApplyingTemplate { ProgressView().controlSize(.small) }
                    else { Image(systemName: "square.grid.2x2").foregroundStyle(Theme.accent) }
                }
                .disabled(isApplyingTemplate)
                .accessibilityLabel("Choose template")

                Button {
                    Task { await load(showSpinner: false) }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .disabled(isRefreshing || isLoading)
                .accessibilityLabel("Refresh file list")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var breadcrumb: String {
        if let openFile { return openFile.path }
        return stack.isEmpty ? "The channel's file workspace" : currentPath
    }

    private func loadTemplates() async {
        guard let api = app.api else { return }
        templates = (try? await api.listWorkbenchTemplates()) ?? []
    }

    private func apply(_ manifest: WorkbenchTemplateManifest) async {
        isApplyingTemplate = true
        defer { isApplyingTemplate = false }
        do {
            for (path, value) in manifest.seed ?? [:] {
                let content: String
                if case .string(let text) = value { content = text }
                else { content = String(decoding: try JSONEncoder.workbench.encode(value), as: UTF8.self) }
                do {
                    _ = try await app.socket.request(resource: "fs.write", params: [
                        "channel_id": channelId, "path": path, "content": content, "if_version": 0,
                    ])
                } catch ResourceError.server(let code, _) where code == "VERSION_CONFLICT" {
                    // Reapplying a template fills gaps without replacing user or bot data.
                }
            }

            var config: [String: JSONValue] = [:]
            var version = 0
            if let raw = try? await app.socket.request(
                resource: "fs.read", params: ["channel_id": channelId, "path": ".workbench.json"]
            ), let file = try? raw.decode(as: FsFile.self),
               let data = file.content.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                config = decoded
                version = file.version
            }
            var bindings = config["bindings"]?.objectValue ?? [:]
            var configs = config["configs"]?.objectValue ?? [:]
            for view in manifest.views {
                if bindings[view.file] == nil { bindings[view.file] = .string("builtin:\(view.lens)") }
                if configs[view.file] == nil, let viewConfig = view.config { configs[view.file] = viewConfig }
                lensBindings[view.file] = view.lens
            }
            let existingPins = config["pinned"]?.arrayValue?.compactMap(\.stringValue) ?? []
            config["environment"] = .string(manifest.id)
            config["bindings"] = .object(bindings)
            config["configs"] = .object(configs)
            config["pinned"] = .array(Array(Set(existingPins + (manifest.pin ?? []))).sorted().map(JSONValue.string))
            let configText = String(decoding: try JSONEncoder.workbench.encode(config), as: UTF8.self)
            _ = try await app.socket.request(resource: "fs.write", params: [
                "channel_id": channelId, "path": ".workbench.json",
                "content": configText, "if_version": version,
            ])
            await load(showSpinner: false)
            if let first = manifest.views.first, let node = find(first.file, in: root) {
                stack = Array(first.file.split(separator: "/").dropLast()).map(String.init)
                openFile = node
            }
            errorText = nil
        } catch {
            errorText = (error as? ResourceError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func find(_ path: String, in nodes: [TreeNode]) -> TreeNode? {
        for node in nodes {
            if node.path == path { return node }
            if let result = find(path, in: node.children) { return result }
        }
        return nil
    }
}

private extension JSONEncoder {
    static var workbench: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

// MARK: - Derived folder tree

/// A node in the tree derived from the flat `fs.ls` paths. Mirrors the web
/// `buildTree` (workbench/panels/FilePanel.tsx) so both clients show the same shape.
struct TreeNode: Identifiable {
    let name: String
    let path: String
    let isDir: Bool
    let sizeBytes: Int
    let children: [TreeNode]

    var id: String { path }

    /// Reference type used only while assembling — nested `struct` mutation would mean
    /// copying whole subtrees on every insert.
    private final class Builder {
        let name: String
        let path: String
        var isDir: Bool
        var sizeBytes = 0
        /// Insertion-ordered children, keyed for O(1) lookup while walking segments.
        var order: [String] = []
        var kids: [String: Builder] = [:]

        init(name: String, path: String, isDir: Bool) {
            self.name = name
            self.path = path
            self.isDir = isDir
        }

        func child(_ segment: String, isDir: Bool) -> Builder {
            if let existing = kids[segment] {
                // A prefix seen earlier as a leaf is really a folder once it gains children.
                if isDir { existing.isDir = true }
                return existing
            }
            let full = path.isEmpty ? segment : "\(path)/\(segment)"
            let node = Builder(name: segment, path: full, isDir: isDir)
            kids[segment] = node
            order.append(segment)
            return node
        }

        func frozen() -> [TreeNode] {
            order
                .compactMap { kids[$0] }
                .map {
                    TreeNode(
                        name: $0.name, path: $0.path, isDir: $0.isDir,
                        sizeBytes: $0.sizeBytes, children: $0.frozen()
                    )
                }
                // Folders first, then files, each alphabetical — same ordering as the web.
                .sorted {
                    $0.isDir != $1.isDir
                        ? $0.isDir
                        : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        }
    }

    static func build(from entries: [FsEntry]) -> [TreeNode] {
        let root = Builder(name: "", path: "", isDir: true)
        for entry in entries {
            let parts = entry.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            var cursor = root
            // Every segment but the last is necessarily a folder.
            for segment in parts.dropLast() {
                cursor = cursor.child(segment, isDir: true)
            }
            let leaf = cursor.child(parts[parts.count - 1], isDir: entry.isDir)
            if !entry.isDir { leaf.sizeBytes = entry.sizeBytes }
        }
        return root.frozen()
    }
}

// MARK: - File contents and native renderers

private struct FileContentView: View {
    @Environment(AppModel.self) private var app
    let channelId: String
    let node: TreeNode
    let preferredLens: String?

    @State private var content: String?
    @State private var errorText: String?
    @State private var isLoading = true
    @State private var selectedLens: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if let errorText {
                ComingSoon(icon: "exclamationmark.triangle", text: errorText)
            } else if let content {
                if content.isEmpty {
                    ComingSoon(icon: "doc", text: "This file is empty.")
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Renderer").font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Menu(lensTitle(activeLens(for: content))) {
                                ForEach(availableLenses(for: content), id: \.self) { lens in
                                    Button(lensTitle(lens)) { selectedLens = lens }
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                        renderer(content, lens: activeLens(for: content))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: node.path) {
            selectedLens = preferredLens
            await load()
        }
    }

    @ViewBuilder
    private func renderer(_ content: String, lens: String) -> some View {
        switch lens {
        case "markdown": MarkdownRenderer(content: content)
        case "table": TableRenderer(content: content)
        case "kanban": KanbanRenderer(content: content)
        case "chart": NativeChartRenderer(content: content)
        default: RawRenderer(content: content)
        }
    }

    private func activeLens(for content: String) -> String {
        selectedLens ?? preferredLens ?? inferredLens(content)
    }

    private func availableLenses(for content: String) -> [String] {
        var values = ["raw"]
        let inferred = inferredLens(content)
        if inferred != "raw" { values.insert(inferred, at: 0) }
        if let preferredLens, !values.contains(preferredLens) { values.insert(preferredLens, at: 0) }
        return values
    }

    private func lensTitle(_ lens: String) -> String {
        lens == "raw" ? "Raw" : lens.capitalized
    }

    private func inferredLens(_ content: String) -> String {
        let ext = node.path.split(separator: ".").last.map(String.init)?.lowercased()
        if ext == "md" || ext == "markdown" { return "markdown" }
        guard let data = content.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return "raw" }
        if value["series"]?.arrayValue != nil { return "chart" }
        if value["columns"]?.arrayValue != nil { return "kanban" }
        if let rows = value.arrayValue, rows.allSatisfy({ $0.objectValue != nil }) { return "table" }
        return "raw"
    }

    private func load() async {
        isLoading = true
        do {
            let raw = try await app.socket.request(
                resource: "fs.read", params: ["channel_id": channelId, "path": node.path])
            content = try raw.decode(as: FsFile.self).content
            errorText = nil
        } catch {
            errorText = (error as? ResourceError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

private struct RawRenderer: View {
    let content: String
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(16)
        }
    }
}

/// Presentation-only Markdown. It recognizes structure but deliberately does not
/// create tappable links from untrusted bot-authored content.
private struct MarkdownRenderer: View {
    let content: String
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(content.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                    markdownLine(String(line))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder private func markdownLine(_ line: String) -> some View {
        if line.hasPrefix("### ") { Text(String(line.dropFirst(4))).font(.headline) }
        else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.title3.bold()) }
        else if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.title2.bold()) }
        else if line.hasPrefix("- [ ] ") { Label(String(line.dropFirst(6)), systemImage: "square") }
        else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            Label(String(line.dropFirst(6)), systemImage: "checkmark.square.fill")
                .foregroundStyle(Theme.textSecondary)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle.fill").font(.system(size: 5))
                Text(String(line.dropFirst(2)))
            }
        } else if line.hasPrefix("> ") {
            Text(String(line.dropFirst(2))).italic().foregroundStyle(Theme.textSecondary).padding(.leading, 10)
        } else {
            Text(line.isEmpty ? " " : line).font(.body).textSelection(.enabled)
        }
    }
}

private struct TableRenderer: View {
    let content: String
    private var rows: [[String: JSONValue]] {
        guard let data = content.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return value.arrayValue?.compactMap(\.objectValue) ?? []
    }
    private var columns: [String] { Array(Set(rows.flatMap(\.keys))).sorted() }
    var body: some View {
        if rows.isEmpty { ComingSoon(icon: "tablecells", text: "No table rows to display.") }
        else {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow { ForEach(columns, id: \.self) { Text($0).font(.caption.bold()) } }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.prefix(200).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(columns, id: \.self) { Text(display(row[$0])).font(.caption).textSelection(.enabled) }
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct KanbanRenderer: View {
    let content: String
    private var columns: [JSONValue] {
        guard let data = content.data(using: .utf8),
              let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return root["columns"]?.arrayValue ?? []
    }
    var body: some View {
        if columns.isEmpty { ComingSoon(icon: "rectangle.3.group", text: "No kanban columns to display.") }
        else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(column.firstString("name", "title") ?? "Column").font(.headline)
                            ForEach(Array((column["items"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, item in
                                Text(item.firstString("title", "name", "text") ?? display(item))
                                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10).background(Theme.bgRaised, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(12).frame(width: 220, alignment: .topLeading)
                        .background(Theme.bgApp, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct NativeChartRenderer: View {
    let content: String
    private struct Point: Identifiable {
        let id = UUID()
        let series: String
        let x: Double
        let y: Double
    }
    private var points: [Point] {
        guard let data = content.data(using: .utf8),
              let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return (root["series"]?.arrayValue ?? []).flatMap { series in
            let name = series["name"]?.stringValue ?? "Series"
            return (series["points"]?.arrayValue ?? []).enumerated().compactMap { index, pair -> Point? in
                guard let values = pair.arrayValue, values.count >= 2, let y = values[1].numberValue else { return nil }
                return Point(series: name, x: values[0].numberValue ?? Double(index), y: y)
            }
        }
    }
    var body: some View {
        if points.isEmpty { ComingSoon(icon: "chart.xyaxis.line", text: "No chart series to display.") }
        else {
            Chart(points) { point in
                LineMark(x: .value("X", point.x), y: .value("Y", point.y))
                    .foregroundStyle(by: .value("Series", point.series))
                PointMark(x: .value("X", point.x), y: .value("Y", point.y))
                    .foregroundStyle(by: .value("Series", point.series))
            }
            .chartLegend(position: .bottom)
            .padding(16)
        }
    }
}

private func display(_ value: JSONValue?) -> String {
    guard let value else { return "" }
    switch value {
    case .null: return "—"
    case .bool(let value): return value ? "true" : "false"
    case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
    case .string(let value): return value
    case .array, .object:
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Remote workspace

struct RemoteWorkspaceSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let channelId: String
    let onAddContext: (ResourceContextItem) -> Void

    private enum Tab: String, CaseIterable { case files = "Files"; case changes = "Changes" }
    @State private var tab: Tab = .files
    @State private var bots: [RemoteWorkspaceBot] = []
    @State private var botId = ""
    @State private var root: String?
    @State private var currentPath = ""
    @State private var entries: [RemoteWorkspaceEntry] = []
    @State private var file: RemoteWorkspaceFile?
    @State private var git: RemoteGitStatus?
    @State private var diffText: String?
    @State private var draft = ""
    @State private var isEditing = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showConflict = false

    private var selectedBot: RemoteWorkspaceBot? { bots.first { $0.botId == botId } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if bots.count > 1 {
                    Picker("Agent", selection: $botId) {
                        ForEach(bots) { bot in
                            Text(bot.name + (bot.online ? "" : " · offline")).tag(bot.botId)
                        }
                    }
                    .pickerStyle(.menu).padding(.horizontal, 16)
                    .onChange(of: botId) { resetAndLoad() }
                }
                Picker("Workspace view", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(12)
                Group {
                    if isLoading { ProgressView() }
                    else if let errorText, entries.isEmpty, file == nil { workspaceUnavailable(errorText) }
                    else if tab == .changes { changesView }
                    else if let file { fileView(file) }
                    else { treeView }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Remote workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if file != nil || !currentPath.isEmpty {
                        Button { goBack() } label: { Image(systemName: "chevron.left") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .task { await loadBots() }
        .confirmationDialog("This file changed on the agent's machine", isPresented: $showConflict) {
            Button("Reload remote version") { Task { await reloadOpenFile() } }
            Button("Overwrite remote version", role: .destructive) { Task { await save(force: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Review the remote version before overwriting whenever possible.")
        }
    }

    private var treeView: some View {
        List {
            if let root {
                Section {
                    Label(root, systemImage: "externaldrive").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Section(currentPath.isEmpty ? "Root" : currentPath) {
                ForEach(entries.sorted { lhs, rhs in
                    lhs.isDir != rhs.isDir ? lhs.isDir : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }) { entry in
                    Button { Task { await open(entry) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.isDir ? "folder.fill" : "doc")
                                .foregroundStyle(entry.isDir ? Theme.accent : Theme.textMuted)
                            Text(entry.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if !entry.isDir {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.sizeBytes), countStyle: .file))
                                    .font(.caption2).foregroundStyle(Theme.textFaint)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .refreshable { await loadTree(path: currentPath) }
    }

    @ViewBuilder
    private func fileView(_ opened: RemoteWorkspaceFile) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(opened.filename).font(.headline).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(opened.sizeBytes), countStyle: .file))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    onAddContext(workspaceContext(opened))
                } label: { Label("Context", systemImage: "link") }
                .buttonStyle(.bordered)
                if opened.isText, selectedBot?.canWrite == true {
                    Button(isEditing ? "Cancel" : "Edit") {
                        isEditing.toggle(); draft = opened.content ?? ""
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8).background(Theme.bgApp, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                HStack {
                    Text("Save is protected by the file's version tag.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Save") { Task { await save(force: false) } }
                        .buttonStyle(.borderedProminent).disabled(isSaving)
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            } else if opened.isText, let content = opened.content {
                RawRenderer(content: content)
            } else {
                ContentUnavailableView(
                    "Binary file", systemImage: "doc",
                    description: Text("Add it to context so an authorized agent can read it on demand.")
                )
            }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(Theme.danger).padding(.horizontal) }
        }
    }

    private var changesView: some View {
        Group {
            if git?.repo == false {
                ContentUnavailableView("Not a Git repository", systemImage: "arrow.triangle.branch", description: Text(git?.reason ?? "Git is unavailable for this root."))
            } else if let diffText {
                VStack(spacing: 8) {
                    HStack { Button("Back to changes") { self.diffText = nil }; Spacer() }.padding(.horizontal)
                    RawRenderer(content: diffText)
                }
            } else {
                List {
                    Section {
                        LabeledContent("Branch", value: git?.branch ?? "(detached)")
                        if let upstream = git?.upstream { LabeledContent("Upstream", value: upstream) }
                        if (git?.ahead ?? 0) > 0 || (git?.behind ?? 0) > 0 {
                            LabeledContent("Sync", value: "↑\(git?.ahead ?? 0) ↓\(git?.behind ?? 0)")
                        }
                    }
                    Section("Changed files") {
                        ForEach(git?.entries ?? []) { entry in
                            HStack {
                                Text(entry.xy).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.accent)
                                Text(entry.path).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        if (git?.entries ?? []).isEmpty { Text("Working tree clean").foregroundStyle(Theme.textSecondary) }
                    }
                    Section {
                        Button("View unstaged diff") { Task { await loadDiff(staged: false) } }
                        Button("View staged diff") { Task { await loadDiff(staged: true) } }
                    }
                }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden)
                .refreshable { await loadGit() }
            }
        }
        .task(id: botId + (root ?? "")) { await loadGit() }
    }

    private func workspaceUnavailable(_ message: String) -> some View {
        ContentUnavailableView("Workspace unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(message))
    }

    private func loadBots() async {
        guard let api = app.api else { isLoading = false; return }
        do {
            bots = try await api.listRemoteWorkspaceBots(channelId: channelId)
            if let first = bots.first(where: { $0.online && $0.canRead }) ?? bots.first(where: \.canRead) {
                botId = first.botId
                await loadTree(path: "")
            } else {
                errorText = "No readable agent workspace is available in this channel."
                isLoading = false
            }
        } catch { fail(error) }
    }

    private func resetAndLoad() {
        root = nil; currentPath = ""; entries = []; file = nil; git = nil; diffText = nil
        Task { await loadTree(path: "") }
    }

    private func loadTree(path: String) async {
        guard let api = app.api, !botId.isEmpty else { return }
        isLoading = true
        do {
            let tree = try await api.remoteWorkspaceTree(
                channelId: channelId, botId: botId, path: path, root: root
            )
            root = tree.root; currentPath = tree.path; entries = tree.entries; file = nil; errorText = nil
        } catch { fail(error) }
        isLoading = false
    }

    private func open(_ entry: RemoteWorkspaceEntry) async {
        if entry.isDir { await loadTree(path: entry.path); return }
        guard let api = app.api else { return }
        isLoading = true
        do {
            file = try await api.remoteWorkspaceFile(
                channelId: channelId, botId: botId, path: entry.path, root: root
            )
            draft = file?.content ?? ""; isEditing = false; errorText = nil
        } catch { fail(error) }
        isLoading = false
    }

    private func goBack() {
        if file != nil { file = nil; isEditing = false; return }
        let parent = currentPath.split(separator: "/").dropLast().joined(separator: "/")
        Task { await loadTree(path: parent) }
    }

    private func reloadOpenFile() async {
        guard let path = file?.path else { return }
        await open(RemoteWorkspaceEntry(name: file?.filename ?? path, path: path, isDir: false, sizeBytes: file?.sizeBytes ?? 0))
    }

    private func save(force: Bool) async {
        guard let api = app.api, let opened = file, selectedBot?.canWrite == true else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await api.writeRemoteWorkspaceFile(
                channelId: channelId, botId: botId, path: opened.path, root: root,
                content: draft, ifMatch: force ? nil : opened.etag
            )
            await reloadOpenFile(); isEditing = false; await loadGit()
        } catch APIError.http(let status, _) where status == 409 {
            showConflict = true
        } catch { fail(error) }
    }

    private func loadGit() async {
        guard let api = app.api, !botId.isEmpty else { return }
        do {
            git = try await api.remoteGitStatus(
                channelId: channelId, botId: botId, path: currentPath, root: root
            )
            errorText = nil
        } catch { fail(error) }
    }

    private func loadDiff(staged: Bool) async {
        guard let api = app.api else { return }
        do {
            let result = try await api.remoteGitDiff(
                channelId: channelId, botId: botId, path: currentPath, staged: staged, root: root
            )
            diffText = result.diff.isEmpty ? "No \(staged ? "staged" : "unstaged") changes." : result.diff
        } catch { fail(error) }
    }

    private func workspaceContext(_ file: RemoteWorkspaceFile) -> ResourceContextItem {
        var params: [String: JSONValue] = ["bot_id": .string(botId), "path": .string(file.path)]
        if let root { params["root"] = .string(root) }
        let owner = selectedBot?.name ?? botId
        return ResourceContextItem(
            id: "ws:\(botId):\(root ?? ""):\(file.path)", verb: "workspace.read",
            params: params, label: "\(file.filename) (@\(owner) workspace)", kind: "file"
        )
    }

    private func fail(_ error: Error) {
        errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        isLoading = false
    }
}
