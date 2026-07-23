import AppKit
import Foundation

final class AppServerClient {
    private static let fallbackRefreshInterval: TimeInterval = 180

    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.codex-usage-overlay.app-server")
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var refreshTimer: DispatchSourceTimer?
    private var restartWorkItem: DispatchWorkItem?
    private var nextRequestID = 1
    private var initialized = false
    private var stopped = false
    private var latestSnapshot: UsageSnapshot?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = false
            self.startProcess()
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            restartWorkItem?.cancel()
            refreshTimer?.cancel()
            refreshTimer = nil
            process?.terminationHandler = nil
            process?.terminate()
            process = nil
            inputHandle = nil
            initialized = false
            latestSnapshot = nil
        }
    }

    func refreshNow() {
        queue.async { [weak self] in self?.requestSnapshot() }
    }

    private func startProcess() {
        guard !stopped, process == nil else { return }
        guard let executable = Self.findCodexExecutable() else {
            publishError("找不到 Codex 内置 app-server")
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.process = nil
                self.inputHandle = nil
                self.initialized = false
                self.latestSnapshot = nil
                self.refreshTimer?.cancel()
                self.refreshTimer = nil
                guard !self.stopped else { return }
                let work = DispatchWorkItem { [weak self] in self?.startProcess() }
                self.restartWorkItem = work
                self.queue.asyncAfter(deadline: .now() + 5, execute: work)
            }
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }

        do {
            try process.run()
            self.process = process
            inputHandle = input.fileHandleForWriting
            send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-usage-overlay",
                        "version": "0.1.0"
                    ],
                    "capabilities": [
                        "experimentalApi": true
                    ]
                ]
            ])
        } catch {
            publishError("无法启动 Codex app-server")
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let json = object as? [String: Any]
            else { continue }
            handle(json)
        }
    }

    private func handle(_ json: [String: Any]) {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            publishError(message)
            return
        }

        if let id = json["id"] as? NSNumber,
           id.intValue == 1,
           json["result"] != nil {
            initialized = true
            send(["method": "initialized"])
            requestSnapshot()
            beginRefreshTimer()
            return
        }

        // Handles both the response to account/rateLimits/read and the
        // account/rateLimits/updated notification when the server emits it.
        if let snapshot = UsageParser.parse(json: json, mergingWith: latestSnapshot) {
            latestSnapshot = snapshot
            DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
        }
    }

    private func beginRefreshTimer() {
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.fallbackRefreshInterval,
            repeating: Self.fallbackRefreshInterval
        )
        timer.setEventHandler { [weak self] in self?.requestSnapshot() }
        timer.resume()
        refreshTimer = timer
    }

    private func requestSnapshot() {
        guard initialized, process != nil else { return }
        send([
            "id": nextID(),
            "method": "account/rateLimits/read",
            "params": NSNull()
        ])
    }

    private func nextID() -> Int {
        nextRequestID += 1
        return nextRequestID
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        data.append(0x0A)
        do {
            try inputHandle?.write(contentsOf: data)
        } catch {
            publishError("Codex app-server 连接中断")
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }

    private static func findCodexExecutable() -> String? {
        var candidates: [String] = []
        for bundleID in ["com.openai.codex", "com.openai.chatgpt"] {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                candidates.append(appURL.appendingPathComponent("Contents/Resources/codex").path)
            }
        }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }
}
