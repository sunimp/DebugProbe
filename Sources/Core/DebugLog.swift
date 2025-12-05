// DebugLog.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

/// DebugProbe 内部日志工具
/// - `info`: 功能启用/禁用等重要信息，始终输出
/// - `debug`: 调试信息，受 `isEnabled` 开关控制（默认关闭）
public enum DebugLog {
    // MARK: - Configuration

    /// 是否启用调试日志（默认关闭）
    /// 功能启用信息（info 级别）不受此开关控制
    public static var isEnabled: Bool = false

    /// 日志前缀
    private static let prefix = "[DebugProbe]"

    // MARK: - Public API

    /// 输出功能启用/禁用等重要信息（受 isEnabled 开关控制）
    /// - Parameter message: 日志消息
    public static func info(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix) \(message())")
    }

    /// 输出调试信息（受 isEnabled 开关控制）
    /// - Parameter message: 日志消息
    public static func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix) \(message())")
    }

    /// 输出警告信息（受 isEnabled 开关控制）
    /// - Parameter message: 日志消息
    public static func warning(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix) ⚠️ \(message())")
    }

    /// 输出错误信息（受 isEnabled 开关控制）
    /// - Parameter message: 日志消息
    public static func error(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix) ❌ \(message())")
    }

    // MARK: - Subsystem Logging

    /// 带子系统标识的日志
    public enum Subsystem {
        case bridge
        case network
        case eventBus
        case persistence
        case breakpoint
        case chaos
        case mock
        case webSocket

        var tag: String {
            switch self {
            case .bridge: "[Bridge]"
            case .network: "[Network]"
            case .eventBus: "[EventBus]"
            case .persistence: "[Persistence]"
            case .breakpoint: "[Breakpoint]"
            case .chaos: "[Chaos]"
            case .mock: "[Mock]"
            case .webSocket: "[WebSocket]"
            }
        }
    }

    /// 输出带子系统标识的重要信息（受开关控制）
    public static func info(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix)\(subsystem.tag) \(message())")
    }

    /// 输出带子系统标识的调试信息（受开关控制）
    public static func debug(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix)\(subsystem.tag) \(message())")
    }

    /// 输出带子系统标识的错误信息（受开关控制）
    public static func error(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("\(prefix)\(subsystem.tag) ❌ \(message())")
    }
}
