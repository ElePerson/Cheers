import SwiftUI
import Charts
import QuickLook

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
    @Environment(\.dismiss) private var dismiss
    let channelId: String

    private enum Route: Hashable {
        case folder(String)
        case file(String)
    }

    @State private var path: [Route] = []
    @State private var root: [TreeNode] = []
    @State private var errorText: String?
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var templates: [WorkbenchTemplateRow] = []
    @State private var isApplyingTemplate = false
    @State private var lensBindings: [String: String] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            browser(nodes: root, title: "Workbench", folderPath: "")
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .folder(let folderPath):
                        if let folder = find(folderPath, in: root) {
                            browser(nodes: folder.children, title: folder.name, folderPath: folderPath)
                        } else {
                            ContentUnavailableView(
                                "Folder unavailable",
                                systemImage: "folder.badge.questionmark",
                                description: Text("The folder may have been moved or deleted.")
                            )
                        }
                    case .file(let filePath):
                        if let file = find(filePath, in: root) {
                            FileContentView(
                                channelId: channelId,
                                node: file,
                                preferredLens: lensBindings[file.path]
                            )
                        } else {
                            ContentUnavailableView(
                                "File unavailable",
                                systemImage: "doc.badge.ellipsis",
                                description: Text("The file may have been moved or deleted.")
                            )
                        }
                    }
                }
        }
        .task {
            async let files: Void = load()
            async let templateList: Void = loadTemplates()
            _ = await (files, templateList)
        }
    }

    @ViewBuilder
    private func browser(nodes: [TreeNode], title: String, folderPath: String) -> some View {
        Group {
            if isLoading && root.isEmpty {
                ProgressView("Loading files…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, root.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load files", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if nodes.isEmpty {
                ContentUnavailableView(
                    "No files",
                    systemImage: "folder",
                    description: Text("Files created in this channel will appear here.")
                )
            } else {
                List(nodes) { node in
                    NavigationLink(value: node.isDir ? Route.folder(node.path) : Route.file(node.path)) {
                        row(node)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(showSpinner: false) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if folderPath.isEmpty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        if templates.isEmpty {
                            Text("No templates installed")
                        } else {
                            ForEach(templates) { template in
                                Button(template.title) { Task { await apply(template.manifest) } }
                            }
                        }
                    } label: {
                        if isApplyingTemplate { ProgressView() }
                        else { Label("Templates", systemImage: "square.grid.2x2") }
                    }
                    .disabled(isApplyingTemplate)

                    Button { Task { await load(showSpinner: false) } } label: {
                        if isRefreshing { ProgressView() }
                        else { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    .disabled(isRefreshing || isLoading)
                }
            }
        }
    }

    private func row(_ node: TreeNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDir ? "folder.fill" : icon(for: node.name))
                .font(.subheadline)
                .foregroundStyle(node.isDir ? Color.accentColor : Color.secondary)
                .frame(width: 22)
            Text(node.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if node.isDir {
                Text("\(node.children.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Text(size(node.sizeBytes))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
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
            normalizeNavigationPath()
            errorText = nil
        } catch {
            errorText = (error as? ResourceError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Keep the deepest still-valid destination after a refresh. If an agent moved
    /// or deleted the open item, SwiftUI pops back to its nearest valid parent.
    private func normalizeNavigationPath() {
        guard let invalidIndex = path.firstIndex(where: { route in
            switch route {
            case .folder(let routePath):
                guard let node = find(routePath, in: root) else { return true }
                return !node.isDir
            case .file(let routePath):
                guard let node = find(routePath, in: root) else { return true }
                return node.isDir
            }
        }) else { return }
        path.removeSubrange(invalidIndex...)
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
                var accumulated = ""
                path = first.file.split(separator: "/").dropLast().map { segment in
                    accumulated = accumulated.isEmpty ? String(segment) : "\(accumulated)/\(segment)"
                    return Route.folder(accumulated)
                }
                path.append(.file(node.path))
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
                ContentUnavailableView("Couldn’t load file", systemImage: "exclamationmark.triangle", description: Text(errorText))
            } else if let content {
                if content.isEmpty {
                    ContentUnavailableView("Empty file", systemImage: "doc")
                } else {
                    renderer(content, lens: activeLens(for: content))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let content, !content.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Renderer", selection: Binding(
                            get: { activeLens(for: content) },
                            set: { selectedLens = $0 }
                        )) {
                            ForEach(availableLenses(for: content), id: \.self) { lens in
                                Text(lensTitle(lens)).tag(lens)
                            }
                        }
                    } label: {
                        Label(lensTitle(activeLens(for: content)), systemImage: "eye")
                    }
                }
            }
        }
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
                .font(.subheadline.monospaced())
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
                Image(systemName: "circle.fill").font(.caption2)
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
    private enum GitMode: String, CaseIterable { case working = "Working"; case history = "History" }
    private enum FileSort: String, CaseIterable { case name = "Name"; case size = "Size"; case kind = "Kind" }
    private enum Route: Hashable {
        case folder(String)
        case file(String)
        case diff(path: String, staged: Bool)
        case commit(String)
        case commitDiff(commit: String, path: String?)
    }
    @State private var tab: Tab = .files
    @State private var gitMode: GitMode = .working
    @State private var fileSort: FileSort = .name
    @State private var fileQuery = ""
    @State private var navigationPath: [Route] = []
    @State private var bots: [RemoteWorkspaceBot] = []
    @State private var botId = ""
    @State private var root: String?
    @State private var currentPath = ""
    @State private var entries: [RemoteWorkspaceEntry] = []
    @State private var file: RemoteWorkspaceFile?
    @State private var git: RemoteGitStatus?
    @State private var gitHistory: [RemoteGitCommit] = []
    @State private var commitFiles: [RemoteGitCommitFile] = []
    @State private var diffText: String?
    @State private var previewURL: URL?
    @State private var previewFiles: [URL] = []
    @State private var draft = ""
    @State private var isEditing = false
    @State private var isInitialLoading = true
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showConflict = false

    private var selectedBot: RemoteWorkspaceBot? { bots.first { $0.botId == botId } }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                Picker("Workspace view", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(12)
                Group {
                    // Only replace the entire surface during the initial agent lookup.
                    // Page-level loads (History, diffs, files) must keep their owning
                    // view mounted or SwiftUI cancels the `.task` that started them.
                    if isInitialLoading { ProgressView() }
                    else if let errorText, entries.isEmpty { workspaceUnavailable(errorText) }
                    else if tab == .changes { changesView }
                    else { treeView(path: "") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Remote workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if bots.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Agent", selection: $botId) {
                                ForEach(bots) { bot in
                                    Text(bot.name + (bot.online ? "" : " · offline")).tag(bot.botId)
                                }
                            }
                        } label: {
                            Label(selectedBot?.name ?? "Agent", systemImage: "desktopcomputer")
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let folderPath):
                    treeView(path: folderPath)
                        .navigationTitle(folderPath.split(separator: "/").last.map(String.init) ?? "Folder")
                        .navigationBarTitleDisplayMode(.inline)
                        .task(id: folderPath) { await loadTree(path: folderPath) }
                case .file(let filePath):
                    remoteFileDestination(path: filePath)
                        .task(id: filePath) { await loadFile(path: filePath) }
                case .diff(let path, let staged):
                    diffView(title: path.isEmpty ? nil : path, staged: staged)
                        .task(id: "\(path):\(staged)") { await loadDiff(path: path, staged: staged) }
                case .commit(let commit):
                    commitView(commit: commit)
                        .task(id: commit) { await loadCommitFiles(commit: commit) }
                case .commitDiff(let commit, let path):
                    diffView(title: path ?? String(commit.prefix(8)), staged: false)
                        .task(id: "\(commit):\(path ?? "")") { await loadCommitDiff(commit: commit, path: path) }
                }
            }
        }
        .task { await loadBots() }
        .onChange(of: tab) {
            navigationPath.removeAll()
            if tab == .changes { Task { await loadGit() } }
            else { Task { await loadTree(path: "") } }
        }
        .onChange(of: botId) { resetAndLoad() }
        .confirmationDialog("This file changed on the agent's machine", isPresented: $showConflict) {
            Button("Reload remote version") { Task { await reloadOpenFile() } }
            Button("Overwrite remote version", role: .destructive) { Task { await save(force: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Review the remote version before overwriting whenever possible.")
        }
        .quickLookPreview($previewURL)
        .onDisappear { removePreviewFiles() }
    }

    private func treeView(path: String) -> some View {
        List {
            if let root {
                Section {
                    Label(root, systemImage: "externaldrive").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Section(path.isEmpty ? "Root" : path) {
                ForEach(visibleEntries) { entry in
                    NavigationLink(value: entry.isDir ? Route.folder(entry.path) : Route.file(entry.path)) {
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(entry))
                                .foregroundStyle(entry.isDir ? Color.accentColor : Color.secondary)
                                .frame(width: 24)
                            Text(entry.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if !entry.isDir {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.sizeBytes), countStyle: .file))
                                    .font(.caption2).foregroundStyle(Theme.textFaint)
                            }
                        }
                    }
                    .contextMenu {
                        if !entry.isDir {
                            Button { Task { await previewFile(path: entry.path) } } label: {
                                Label("Quick Look", systemImage: "eye")
                            }
                            Button { Task { await addFileToContext(path: entry.path) } } label: {
                                Label("Add to context", systemImage: "link.badge.plus")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $fileQuery, prompt: "Search this folder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $fileSort) {
                        ForEach(FileSort.allCases, id: \.self) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .refreshable { await loadTree(path: path) }
        .onAppear {
            if currentPath != path { Task { await loadTree(path: path) } }
        }
    }

    private var visibleEntries: [RemoteWorkspaceEntry] {
        let filtered = fileQuery.isEmpty ? entries : entries.filter {
            $0.name.localizedCaseInsensitiveContains(fileQuery)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isDir != rhs.isDir { return lhs.isDir }
            switch fileSort {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes < rhs.sizeBytes }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .kind:
                let left = lhs.name.split(separator: ".").last.map(String.init) ?? ""
                let right = rhs.name.split(separator: ".").last.map(String.init) ?? ""
                if left != right { return left.localizedCaseInsensitiveCompare(right) == .orderedAscending }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func fileIcon(_ entry: RemoteWorkspaceEntry) -> String {
        if entry.isDir { return "folder.fill" }
        switch entry.name.split(separator: ".").last.map(String.init)?.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic": return "photo"
        case "mov", "mp4", "m4v": return "film"
        case "mp3", "m4a", "wav": return "waveform"
        case "pdf": return "doc.richtext"
        case "swift", "rs", "js", "ts", "py", "json", "yaml", "yml": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }

    @ViewBuilder
    private func remoteFileDestination(path: String) -> some View {
        if isLoading {
            ProgressView("Loading file…")
        } else if let file {
            fileView(file)
                .navigationTitle(file.filename)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("File unavailable", systemImage: "doc.badge.ellipsis")
        }
    }

    @ViewBuilder
    private func fileView(_ opened: RemoteWorkspaceFile) -> some View {
        VStack(spacing: 8) {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.subheadline.monospaced())
                    .padding()
            } else if opened.isText, let content = opened.content {
                RawRenderer(content: content)
            } else {
                ContentUnavailableView(
                    "Binary file", systemImage: "doc",
                    description: Text("Add it to context so an authorized agent can read it on demand.")
                )
            }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { prepareQuickLook(opened) } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                Button { onAddContext(workspaceContext(opened)) } label: {
                    Label("Add to context", systemImage: "link.badge.plus")
                }
                if opened.isText, selectedBot?.canWrite == true {
                    if isEditing {
                        Button("Cancel") { isEditing = false }
                        Button(isSaving ? "Saving…" : "Save") { Task { await save(force: false) } }
                            .disabled(isSaving)
                    } else {
                        Button("Edit") {
                            draft = opened.content ?? ""
                            isEditing = true
                        }
                    }
                }
            }
        }
    }

    private var changesView: some View {
        VStack(spacing: 0) {
            Picker("Git view", selection: $gitMode) {
                ForEach(GitMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if git?.repo == false {
                ContentUnavailableView("Not a Git repository", systemImage: "arrow.triangle.branch", description: Text(git?.reason ?? "Git is unavailable for this root."))
            } else if let errorText, git == nil || (gitMode == .history && gitHistory.isEmpty) {
                ContentUnavailableView(
                    "Couldn’t load Git data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorText)
                )
            } else if gitMode == .history {
                historyView
            } else {
                workingChangesView
            }
        }
        .task(id: "\(botId):\(root ?? ""): \(gitMode.rawValue)") {
            if gitMode == .history { await loadGitHistory() }
            else { await loadGit() }
        }
    }

    @ViewBuilder
    private var workingChangesView: some View {
        List {
            Section {
                LabeledContent("Branch", value: git?.branch ?? "(detached)")
                if let upstream = git?.upstream { LabeledContent("Upstream", value: upstream) }
                if (git?.ahead ?? 0) > 0 || (git?.behind ?? 0) > 0 {
                    LabeledContent("Sync", value: "↑\(git?.ahead ?? 0) ↓\(git?.behind ?? 0)")
                }
            }
            if !stagedEntries.isEmpty {
                Section("Staged · \(stagedEntries.count)") {
                    ForEach(stagedEntries) { changeRow($0, staged: true) }
                    NavigationLink("Review all staged changes", value: Route.diff(path: "", staged: true))
                }
            }
            if !unstagedEntries.isEmpty {
                Section("Unstaged · \(unstagedEntries.count)") {
                    ForEach(unstagedEntries) { changeRow($0, staged: false) }
                    NavigationLink("Review all unstaged changes", value: Route.diff(path: "", staged: false))
                }
            }
            if stagedEntries.isEmpty && unstagedEntries.isEmpty {
                Section {
                    ContentUnavailableView("Working tree clean", systemImage: "checkmark.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadGit() }
    }

    private var historyView: some View {
        List(gitHistory) { commit in
            NavigationLink(value: Route.commit(commit.hash)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.subject).font(.body.weight(.medium)).lineLimit(2)
                    HStack {
                        Text(commit.author)
                        Text(String(commit.hash.prefix(8))).font(.caption.monospaced())
                        Spacer()
                        Text(commitDate(commit.date))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .listStyle(.plain)
        .refreshable { await loadGitHistory() }
        .overlay {
            if isLoading {
                ProgressView("Loading history…")
            } else if gitHistory.isEmpty {
                ContentUnavailableView("No commits", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    @ViewBuilder
    private func changeRow(_ entry: RemoteGitStatusEntry, staged: Bool) -> some View {
        if entry.xy == "??" {
            NavigationLink(value: Route.file(entry.path)) {
                gitFileLabel(entry, status: "U")
            }
        } else {
            NavigationLink(value: Route.diff(path: entry.path, staged: staged)) {
                gitFileLabel(entry, status: staged ? String(entry.xy.prefix(1)) : String(entry.xy.suffix(1)))
            }
        }
    }

    private func gitFileLabel(_ entry: RemoteGitStatusEntry, status: String) -> some View {
        HStack(spacing: 10) {
            Text(status.trimmingCharacters(in: .whitespaces).isEmpty ? "M" : status)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(gitStatusColor(status))
                .frame(width: 20)
            Text(entry.path).lineLimit(1).truncationMode(.middle)
        }
    }

    private var stagedEntries: [RemoteGitStatusEntry] {
        (git?.entries ?? []).filter {
            guard $0.xy != "??", let first = $0.xy.first else { return false }
            return first != " " && first != "."
        }
    }

    private var unstagedEntries: [RemoteGitStatusEntry] {
        (git?.entries ?? []).filter {
            if $0.xy == "??" { return true }
            guard $0.xy.count > 1 else { return false }
            let second = $0.xy[$0.xy.index(after: $0.xy.startIndex)]
            return second != " " && second != "."
        }
    }

    private func gitStatusColor(_ status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespaces).first {
        case "A", "?": .green
        case "D": .red
        case "R": .blue
        default: .orange
        }
    }

    @ViewBuilder
    private func diffView(title: String?, staged: Bool) -> some View {
        Group {
            if isLoading {
                ProgressView("Loading diff…")
            } else if let diffText, !diffText.isEmpty {
                GitPatchView(diff: diffText)
            } else if let errorText {
                ContentUnavailableView("Couldn’t load diff", systemImage: "exclamationmark.triangle", description: Text(errorText))
            } else {
                ContentUnavailableView("No changes", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle(title ?? (staged ? "Staged review" : "Changes review"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func commitView(commit: String) -> some View {
        if isLoading {
            ProgressView("Loading commit…")
        } else if commitFiles.isEmpty {
            ContentUnavailableView("No changed files", systemImage: "doc")
        } else {
            List {
                Section {
                    NavigationLink("Review full commit", value: Route.commitDiff(commit: commit, path: nil))
                }
                Section("Changed files · \(commitFiles.count)") {
                    ForEach(commitFiles) { item in
                        NavigationLink(value: Route.commitDiff(commit: commit, path: item.path)) {
                            HStack(spacing: 10) {
                                Text(String(item.status.prefix(1)))
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(gitStatusColor(item.status))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.path).lineLimit(1).truncationMode(.middle)
                                    if let oldPath = item.oldPath {
                                        Text("from \(oldPath)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func commitDate(_ raw: String) -> String {
        guard let date = TimeFormat.parse(raw) else { return raw }
        return TimeFormat.listStamp(date)
    }

    private func workspaceUnavailable(_ message: String) -> some View {
        ContentUnavailableView("Workspace unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(message))
    }

    private func loadBots() async {
        defer { isInitialLoading = false }
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
        root = nil; currentPath = ""; entries = []; file = nil; git = nil
        gitHistory = []; commitFiles = []; diffText = nil; navigationPath = []
        Task { await loadTree(path: "") }
    }

    private func loadTree(path: String) async {
        guard let api = app.api, !botId.isEmpty else { return }
        isLoading = true
        do {
            let tree = try await api.remoteWorkspaceTree(
                channelId: channelId, botId: botId, path: path, root: root
            )
            if currentPath != tree.path { fileQuery = "" }
            root = tree.root; currentPath = tree.path; entries = tree.entries; file = nil; errorText = nil
        } catch { fail(error) }
        isLoading = false
    }

    private func loadFile(path: String) async {
        guard let api = app.api else { return }
        isLoading = true
        do {
            file = try await api.remoteWorkspaceFile(
                channelId: channelId, botId: botId, path: path, root: root
            )
            draft = file?.content ?? ""; isEditing = false; errorText = nil
            if let file { prepareQuickLook(file) }
        } catch { fail(error) }
        isLoading = false
    }

    private func reloadOpenFile() async {
        guard let path = file?.path else { return }
        await loadFile(path: path)
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

    private func loadDiff(path: String, staged: Bool) async {
        guard let api = app.api else { return }
        isLoading = true
        diffText = nil
        defer { isLoading = false }
        do {
            let result = try await api.remoteGitDiff(
                channelId: channelId, botId: botId, path: path, staged: staged, root: root
            )
            diffText = result.diff
            errorText = nil
        } catch { fail(error) }
    }

    private func loadGitHistory() async {
        guard let api = app.api, !botId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            gitHistory = try await api.remoteGitLog(
                channelId: channelId, botId: botId, root: root
            ).commits
            errorText = nil
        } catch { fail(error) }
    }

    private func loadCommitFiles(commit: String) async {
        guard let api = app.api else { return }
        isLoading = true
        commitFiles = []
        defer { isLoading = false }
        do {
            commitFiles = try await api.remoteGitCommitFiles(
                channelId: channelId, botId: botId, commit: commit, root: root
            ).files
            errorText = nil
        } catch { fail(error) }
    }

    private func loadCommitDiff(commit: String, path: String?) async {
        guard let api = app.api else { return }
        isLoading = true
        diffText = nil
        defer { isLoading = false }
        do {
            diffText = try await api.remoteGitShow(
                channelId: channelId, botId: botId, commit: commit, path: path, root: root
            ).diff
            errorText = nil
        } catch { fail(error) }
    }

    private func previewFile(path: String) async {
        guard let api = app.api else { return }
        do {
            let opened = try await api.remoteWorkspaceFile(
                channelId: channelId, botId: botId, path: path, root: root
            )
            prepareQuickLook(opened)
        } catch { fail(error) }
    }

    private func addFileToContext(path: String) async {
        guard let api = app.api else { return }
        do {
            let opened = try await api.remoteWorkspaceFile(
                channelId: channelId, botId: botId, path: path, root: root
            )
            onAddContext(workspaceContext(opened))
        } catch { fail(error) }
    }

    private func prepareQuickLook(_ opened: RemoteWorkspaceFile) {
        guard let data = Data(base64Encoded: opened.contentBase64) else {
            errorText = "This file could not be prepared for preview."
            return
        }
        removePreviewFile()
        let safeName = URL(fileURLWithPath: opened.filename).lastPathComponent
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cheers-preview-\(UUID().uuidString)-\(safeName)")
        do {
            try data.write(to: url, options: .atomic)
            previewFiles.append(url)
            previewURL = url
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func removePreviewFile() {
        guard let previewURL else { return }
        try? FileManager.default.removeItem(at: previewURL)
        previewFiles.removeAll { $0 == previewURL }
        self.previewURL = nil
    }

    private func removePreviewFiles() {
        previewFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        previewFiles.removeAll()
        previewURL = nil
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

private struct GitPatchView: View {
    private struct Line: Identifiable {
        enum Kind { case addition, deletion, hunk, header, context }
        let id: Int
        let text: String
        let kind: Kind
    }

    let diff: String

    private var lines: [Line] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, raw in
            let text = String(raw)
            let kind: Line.Kind
            if text.hasPrefix("+++") || text.hasPrefix("---") || text.hasPrefix("diff ") || text.hasPrefix("index ") {
                kind = .header
            } else if text.hasPrefix("@@") {
                kind = .hunk
            } else if text.hasPrefix("+") {
                kind = .addition
            } else if text.hasPrefix("-") {
                kind = .deletion
            } else {
                kind = .context
            }
            return Line(id: index, text: text, kind: kind)
        }
    }

    private var additions: Int { lines.filter { $0.kind == .addition }.count }
    private var deletions: Int { lines.filter { $0.kind == .deletion }.count }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("+\(additions)", systemImage: "plus")
                        .foregroundStyle(.green)
                    Label("−\(deletions)", systemImage: "minus")
                        .foregroundStyle(.red)
                    Spacer()
                    Text("\(lines.count) lines").foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
            Section("Patch") {
                ForEach(lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(foreground(line.kind))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(background(line.kind))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
    }

    private func foreground(_ kind: Line.Kind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .blue
        case .header: .secondary
        case .context: .primary
        }
    }

    private func background(_ kind: Line.Kind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.08)
        case .deletion: Color.red.opacity(0.08)
        case .hunk: Color.blue.opacity(0.08)
        default: Color.clear
        }
    }
}
