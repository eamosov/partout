// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if os(macOS)
import Foundation

/// macOS implementation of YdtunRunner that spawns the ydtun binary as a child process.
public final class ProcessYdtunRunner: YdtunRunner, @unchecked Sendable {
    private let binaryPath: String
    private let lock = NSLock()
    private var process: Process?

    public private(set) var lastErrorCode: Int32 = 0

    public init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    public func start(arguments: [String], environment: [String: String]) async throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = arguments
        proc.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        process = proc

        // Forward ydtun output to NSLog line by line
        Task.detached { [weak self] in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        NSLog("ydtun: %@", trimmed)
                    }
                }
            }
            proc.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
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
