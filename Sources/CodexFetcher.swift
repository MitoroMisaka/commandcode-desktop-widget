import Foundation

enum CodexFetcher {
    /// Spawns Codex app-server, sends a JSON-RPC initialize request,
    /// and parses the response into a CodexStatus.
    /// Uses readabilityHandler (never availableData) to avoid permanent blocking.
    /// Has a 10-second timeout; terminates the process on timeout or completion.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var responseData = Data()
        var hasResumed = false
        var timeoutWorkItem: DispatchWorkItem?

        func isResumed() -> Bool {
            lock.lock(); defer { lock.unlock() }
            return hasResumed
        }
        func markResumed() {
            lock.lock(); defer { lock.unlock() }
            hasResumed = true
        }
        func cancelTimeout() {
            lock.lock(); defer { lock.unlock() }
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil  // break retain cycle
        }
        func storeTimeout(_ item: DispatchWorkItem) {
            lock.lock(); defer { lock.unlock() }
            timeoutWorkItem = item
        }
        func appendData(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            responseData.append(data)
        }
        func snapshotData() -> Data {
            lock.lock(); defer { lock.unlock() }
            return responseData
        }
    }

    static func fetch() async -> CodexStatus? {
        await withCheckedContinuation { continuation in
            let state = State()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
            process.arguments = ["app-server"]

            let stdoutPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardInput = stdinPipe

            // ── Parsing ──────────────────────────────────────────

            @Sendable func parseAndFinish() {
                guard !state.isResumed() else { return }
                let text = String(data: state.snapshotData(), encoding: .utf8) ?? ""
                let lines = text.components(separatedBy: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          let lineData = trimmed.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let id = json["id"] as? Int,
                          id == 1
                    else { continue }

                    // Success: extract result
                    if let result = json["result"] as? [String: Any],
                       let resultData = try? JSONSerialization.data(withJSONObject: result),
                       let initResult = try? JSONDecoder().decode(CodexInitResult.self, from: resultData)
                    {
                        finish(CodexStatus.from(rpcResult: initResult))
                        return
                    }

                    // JSON-RPC error
                    if let errorObj = json["error"] as? [String: Any],
                       let msg = errorObj["message"] as? String
                    {
                        finish(CodexStatus.failed("Codex RPC error: \(msg)"))
                        return
                    }
                }
            }

            @Sendable func finish(_ status: CodexStatus) {
                guard !state.isResumed() else { return }
                state.markResumed()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                state.cancelTimeout()
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(returning: status)
            }

            // ── stdout: readabilityHandler (NEVER availableData) ─

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // EOF – process closed its stdout
                    parseAndFinish()
                    if !state.isResumed() {
                        finish(CodexStatus.failed("Codex closed connection without valid response"))
                    }
                    return
                }
                state.appendData(data)
                parseAndFinish()
            }

            // ── Process termination (set before run to cover all exit paths) ──

            process.terminationHandler = { proc in
                parseAndFinish()
                if !state.isResumed() {
                    let reason: String
                    if proc.terminationStatus != 0 {
                        reason = "Codex exited with status \(proc.terminationStatus)"
                    } else {
                        reason = "Codex exited without valid response"
                    }
                    finish(CodexStatus.failed(reason))
                }
            }

            // ── Launch ───────────────────────────────────────────

            do {
                try process.run()
            } catch {
                finish(CodexStatus.failed("Failed to launch Codex: \(error.localizedDescription)"))
                return
            }

            // ── Send JSON-RPC initialize ─────────────────────────

            let request: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": ["protocolVersion": "0.2.0"],
            ]
            if var requestData = try? JSONSerialization.data(withJSONObject: request) {
                requestData.append(0x0A) // newline delimiter
                stdinPipe.fileHandleForWriting.write(requestData)
            }
            try? stdinPipe.fileHandleForWriting.close()

            // ── 10-second timeout ────────────────────────────────

            let workItem = DispatchWorkItem {
                if !state.isResumed() {
                    finish(CodexStatus.failed("Codex request timed out after 10 seconds"))
                }
            }
            state.storeTimeout(workItem)
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: workItem)
        }
    }
}
