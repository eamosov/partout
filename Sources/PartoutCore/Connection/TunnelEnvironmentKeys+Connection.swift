// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

extension TunnelEnvironmentKeys {
    public static let connectionStatus = TunnelEnvironmentKey<ConnectionStatus>("connectionStatus")

    public static let connectionSubStatus = TunnelEnvironmentKey<String>("connectionSubStatus")

    public static let dataCount = TunnelEnvironmentKey<DataCount>("dataCount")

    public static let lastErrorCode = TunnelEnvironmentKey<PartoutError.Code>("lastErrorCode")

    public static let ydtunAlive = TunnelEnvironmentKey<Bool>("ydtunAlive")

    public static let ydtunApiPort = TunnelEnvironmentKey<UInt16>("ydtunApiPort")
}
