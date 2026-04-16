// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

extension OpenVPNModule {
    public final class Implementation: ModuleImplementation, Sendable {
        public let moduleHandlerId: ModuleType = .openVPN

        public let importerBlock: @Sendable () -> ModuleImporter

        public let connectionBlock: @Sendable (ConnectionParameters, OpenVPNModule) throws -> Connection

        public let singBoxRunnerBlock: (@Sendable () -> SingBoxRunner)?

        public let ydtunRunnerBlock: (@Sendable () -> YdtunRunner)?

        public init(
            importerBlock: @escaping @Sendable () -> ModuleImporter,
            connectionBlock: @escaping @Sendable (ConnectionParameters, OpenVPNModule) throws -> Connection,
            singBoxRunnerBlock: (@Sendable () -> SingBoxRunner)? = nil,
            ydtunRunnerBlock: (@Sendable () -> YdtunRunner)? = nil
        ) {
            self.importerBlock = importerBlock
            self.connectionBlock = connectionBlock
            self.singBoxRunnerBlock = singBoxRunnerBlock
            self.ydtunRunnerBlock = ydtunRunnerBlock
        }
    }
}

extension OpenVPNModule.Implementation: ModuleImporter {
    public func module(fromContents contents: String, object: Any?) throws -> Module {
        try importerBlock().module(fromContents: contents, object: object)
    }
}
