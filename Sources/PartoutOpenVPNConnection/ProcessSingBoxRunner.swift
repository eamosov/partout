// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if os(macOS)
import Foundation

/// SingBoxRunner implementation that spawns the sing-box binary as a child process.
/// This mirrors SingBoxProcess.java from ics-openvpn.
///
/// Only available on macOS where Process spawning is allowed.
/// On iOS, use LibSingBoxRunner with the embedded xcframework instead.
public final class ProcessSingBoxRunner: SingBoxRunner, @unchecked Sendable {
    private let binaryPath: String
    private let lock = NSLock()
    private var process: Process?

    /// Creates a runner with the path to the sing-box binary.
    /// - Parameter binaryPath: Absolute path to the `sing-box` executable.
    public init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    public func start(configJSON: String) async throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }

        // Write config to temp file (matching SingBoxProcess.java)
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("singbox_config.json")
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["run", "-c", configURL.path]

        // Capture output for logging
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        process = proc

        // Log output in background (matching SingBoxProcess.java's log thread)
        Task.detached { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                NSLog("SingBox process: %@", output)
            }
            // Mark as not running when process exits
            self?.lock.lock()
            self?.process = nil
            self?.lock.unlock()
        }
    }

    public func stop() async {
        lock.lock()
        defer { lock.unlock() }

        guard let proc = process else { return }
        proc.terminate()
        proc.waitUntilExit()
        process = nil
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }
}
#endif
