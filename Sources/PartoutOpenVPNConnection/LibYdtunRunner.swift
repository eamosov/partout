// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if canImport(_PartoutYdtun_C)
import Foundation

/// iOS implementation of YdtunRunner using the embedded ydtun Rust static library.
///
/// Calls the ydtun C API (ydtun_start/stop/is_running) which runs the
/// tokio async runtime in-process within the Network Extension.
public final class LibYdtunRunner: YdtunRunner, @unchecked Sendable {
    private let backend = YdtunBackend()
    private let lock = NSLock()
    private var _isRunning = false

    /// Last error code from ydtun_start (0=success, negative=error).
    /// Error codes: -1=mutex, -2=already running, -3=bad UTF8, -4=config parse,
    /// -5=tunnel config, -6=runtime, -7=tunnel start, -99=panic
    public private(set) var lastErrorCode: Int32 = 0

    public init() {}

    public func start(arguments: [String], environment: [String: String]) async throws {
        lock.lock()
        guard !_isRunning else {
            lock.unlock()
            lastErrorCode = -2
            throw PartoutError(.OpenVPN.connectionFailure)
        }
        lock.unlock()

        let args = arguments.joined(separator: " ")

        // Install log callback to forward ydtun tracing to pp_log
        backend.installLogCallback()

        // Run ydtun_start on a dedicated thread because it calls
        // tokio runtime.block_on() which must not run inside an async context
        let backend = self.backend
        let result: Int32 = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let r = backend.start(args: args)
                continuation.resume(returning: r)
            }
        }

        lastErrorCode = result
        guard result == 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }

        lock.lock()
        _isRunning = true
        lock.unlock()
    }

    public func stop() async {
        lock.lock()
        guard _isRunning else {
            lock.unlock()
            return
        }
        lock.unlock()

        backend.stop()

        lock.lock()
        _isRunning = false
        lock.unlock()
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning && backend.isRunning
    }
}
#endif
