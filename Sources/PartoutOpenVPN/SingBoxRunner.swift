// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Protocol for running the sing-box binary/library.
///
/// On Android, this spawns a process. On iOS, this should call
/// the sing-box C API from a compiled xcframework.
public protocol SingBoxRunner: AnyObject, Sendable {

    /// Starts sing-box with the given JSON configuration.
    func start(configJSON: String) async throws

    /// Stops the running sing-box instance.
    func stop() async

    /// Whether sing-box is currently running.
    var isRunning: Bool { get }
}
