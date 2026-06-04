import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct WorkspaceService {
    func createWorkspace() -> WorkspaceLocation? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the project folder where the workflow workspace should be initialized."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let name = promptWorkspaceName(defaultName: url.lastPathComponent)
        guard !name.isEmpty else { return nil }

        let metadataURL = metadataURL(for: name, in: url.path)
        try? FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        return WorkspaceLocation(name: name, path: url.path, metadataPath: metadataURL.path)
    }

    func openExistingWorkspace() -> WorkspaceLocation? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder that contains .workflow-* workspaces."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let workspaces = discoverWorkspaces(in: url)
        if workspaces.isEmpty {
            showNoWorkspaceAlert(projectName: url.lastPathComponent)
            return nil
        }
        if workspaces.count == 1 {
            return workspaces[0]
        }
        return chooseWorkspace(from: workspaces)
    }

    func chooseFiles() -> [MediaAsset] {
        chooseFiles(allowedContentTypes: nil, message: "Choose media, documents, or project files to attach.")
    }

    func chooseFiles(for modality: Modality) -> [MediaAsset] {
        chooseFiles(allowedContentTypes: allowedContentTypes(for: modality), message: "Choose \(modality.title.lowercased()) files to import.")
            .filter { $0.modality == modality }
    }

    private func chooseFiles(allowedContentTypes: [UTType]?, message: String) -> [MediaAsset] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = message
        if let allowedContentTypes {
            panel.allowedContentTypes = allowedContentTypes
        }

        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { url in
            MediaAsset(
                name: url.lastPathComponent,
                path: url.path,
                modality: MediaAsset.inferModality(path: url.path)
            )
        }
    }

    private func allowedContentTypes(for modality: Modality) -> [UTType] {
        switch modality {
        case .image:
            [.image]
        case .video, .audioVideo:
            [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case .audio, .music:
            [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
        case .text:
            [.plainText, .text]
        case .file, .json, .embedding, .scores, .threeD, .mask, .bbox, .reference, .unknown:
            [.data, .item]
        }
    }

    func openFinder(path: String) {
        NSWorkspace.shared.open(URL(filePath: path, directoryHint: .isDirectory))
    }

    func workflowURL(for workspace: WorkspaceLocation) -> URL {
        metadataURL(for: workspace.name, in: workspace.path, explicitPath: workspace.metadataPath)
            .appending(path: "workflow.json")
    }

    func preparedWorkspace(_ workspace: WorkspaceLocation) -> WorkspaceLocation {
        var updated = workspace
        let directory = metadataURL(for: workspace.name, in: workspace.path, explicitPath: workspace.metadataPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        updated.metadataPath = directory.path
        return updated
    }

    func writeWorkflow(_ workflow: WorkflowDocument, for workspace: WorkspaceLocation) {
        let directory = metadataURL(for: workspace.name, in: workspace.path, explicitPath: workspace.metadataPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.workflow.encode(workflow) {
            try? data.write(to: directory.appending(path: "workflow.json"), options: [.atomic])
        }
    }

    func readWorkflow(for workspace: WorkspaceLocation) -> WorkflowDocument? {
        let url = workflowURL(for: workspace)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkflowDocument.self, from: data)
    }

    func discoverWorkspaces(in projectURL: URL) -> [WorkspaceLocation] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        )) ?? []

        return items.compactMap { url in
            guard url.lastPathComponent.hasPrefix(".workflow-"),
                  url.lastPathComponent != ".workflow-assets" else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let name = String(url.lastPathComponent.dropFirst(".workflow-".count))
            return WorkspaceLocation(name: name, path: projectURL.path, metadataPath: url.path)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func renamedWorkspace(_ workspace: WorkspaceLocation, name: String) -> WorkspaceLocation {
        let cleaned = sanitizedWorkspaceName(name)
        guard !cleaned.isEmpty, cleaned != workspace.name else { return workspace }

        var updated = workspace
        let oldURL = metadataURL(for: workspace.name, in: workspace.path, explicitPath: workspace.metadataPath)
        let newURL = metadataURL(for: cleaned, in: workspace.path)
        if FileManager.default.fileExists(atPath: oldURL.path), !FileManager.default.fileExists(atPath: newURL.path) {
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
        } else {
            try? FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        }
        updated.name = cleaned
        updated.metadataPath = newURL.path
        return updated
    }

    func openVSCode(path: String) {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: URL(filePath: "/Applications/Visual Studio Code.app"), configuration: configuration)
    }

    func openApp(named appName: String, path: String?) {
        let target = path.map { URL(filePath: $0, directoryHint: .isDirectory) }
        let configuration = NSWorkspace.OpenConfiguration()
        if let target {
            NSWorkspace.shared.open([target], withApplicationAt: URL(filePath: "/Applications/\(appName).app"), configuration: configuration)
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    func openTerminal(path: String) {
        runProcess("/usr/bin/open", arguments: ["-a", "Terminal", path])
    }

    func launchAgentTUI(agent: AgentConfig, workspacePath: String?) {
        let command = agent.invocationTemplate.replacingOccurrences(of: "{executable}", with: agent.path ?? agent.executable)
        let workingDirectory = workspacePath ?? FileManager.default.homeDirectoryForCurrentUser.path
        let terminalCommand = """
        cd \(shellQuoted(workingDirectory)) || exit 1
        clear
        echo "Launching \(agent.name) in \(workingDirectory)"
        echo ""
        \(command)
        """
        let script = """
        tell application "Terminal"
            activate
            do script \(appleScriptQuoted(terminalCommand))
        end tell
        """
        runProcess("/usr/bin/osascript", arguments: ["-e", script])
    }

    private func runProcess(_ launchPath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments
        try? process.run()
    }

    private func promptWorkspaceName(defaultName: String) -> String {
        let alert = NSAlert()
        alert.messageText = "New Workspace"
        alert.informativeText = "Name this workspace. The app will create a .workflow-name folder inside the selected project folder."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = sanitizedWorkspaceName(defaultName)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return "" }
        return sanitizedWorkspaceName(field.stringValue)
    }

    private func chooseWorkspace(from workspaces: [WorkspaceLocation]) -> WorkspaceLocation? {
        let alert = NSAlert()
        alert.messageText = "Open Workspace"
        alert.informativeText = "Choose an existing workflow workspace."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        for workspace in workspaces {
            popup.addItem(withTitle: workspace.name)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return workspaces[safe: popup.indexOfSelectedItem]
    }

    private func showNoWorkspaceAlert(projectName: String) {
        let alert = NSAlert()
        alert.messageText = "No Workspaces Found"
        alert.informativeText = "\(projectName) does not contain any .workflow-* folders."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func metadataURL(for name: String, in path: String, explicitPath: String? = nil) -> URL {
        if let explicitPath {
            return URL(filePath: explicitPath, directoryHint: .isDirectory)
        }
        return URL(filePath: path, directoryHint: .isDirectory)
            .appending(path: ".workflow-\(sanitizedWorkspaceName(name))", directoryHint: .isDirectory)
    }

    private func sanitizedWorkspaceName(_ value: String) -> String {
        let fallback = "Workspace"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\")
        let cleaned = trimmed.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? fallback : cleaned
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension JSONEncoder {
    static var workflow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptQuoted(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
}
