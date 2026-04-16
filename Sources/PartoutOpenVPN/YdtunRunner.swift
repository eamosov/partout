// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Protocol for running the ydtun binary/library.
///
/// On iOS, this runs the ydtun binary bundled as a framework.
/// On macOS, this spawns ydtun as a child process.
public protocol YdtunRunner: AnyObject, Sendable {

    /// Starts ydtun with the given arguments and environment.
    func start(arguments: [String], environment: [String: String]) async throws

    /// Stops the running ydtun instance.
    func stop() async

    /// Whether ydtun is currently running.
    var isRunning: Bool { get }

    /// Last error code from start() (0=success, negative=error).
    var lastErrorCode: Int32 { get }
}
