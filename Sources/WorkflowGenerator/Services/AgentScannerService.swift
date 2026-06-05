import Foundation

struct AgentScannerService {
    func scan(candidates: [AgentConfig]) async -> [AgentConfig] {
        await withTaskGroup(of: AgentConfig.self) { group in
            for candidate in candidates {
                group.addTask {
                    var updated = candidate
                    let path = await resolveExecutable(candidate.executable)
                    updated.path = path
                    updated.isAvailable = path != nil
                    return updated
                }
            }

            var results: [AgentConfig] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.name < $1.name }
        }
    }
}

private func resolveExecutable(_ executable: String) async -> String? {
    await Task.detached {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(agentScannerShellQuoted(executable))"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }.value
}

private func agentScannerShellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
