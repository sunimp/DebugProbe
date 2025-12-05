// AppLogger.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation
import os.log

/// os_log 包装器，同时写入系统日志和 DebugEventBus
public struct AppLogger {
    // MARK: - Properties

    public let subsystem: String
    public let category: String

    private let osLog: OSLog

    // MARK: - Lifecycle

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        osLog = OSLog(subsystem: subsystem, category: category)
    }

    // MARK: - Logging Methods

    /// 记录日志
    public func log(
        level: LogEvent.Level,
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // 1. 写入 os_log
        os_log("%{public}@", log: osLog, type: mapLevelToOSLogType(level), message)

        // 2. 同步发送到 DebugEventBus
        let event = LogEvent(
            id: UUID().uuidString,
            source: .osLog,
            timestamp: Date(),
            level: level,
            subsystem: subsystem,
            category: category,
            loggerName: nil,
            thread: Thread.isMainThread ? "main" : Thread.current.description,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line,
            message: message,
            tags: tags,
            traceId: traceId ?? Thread.debugProbeTraceId
        )
        DebugEventBus.shared.enqueue(.log(event))
    }

    // MARK: - Convenience Methods

    public func debug(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    public func info(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    public func warning(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    public func error(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    public func verbose(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .verbose, message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    // MARK: - Helpers

    private func mapLevelToOSLogType(_ level: LogEvent.Level) -> OSLogType {
        switch level {
        case .verbose:
            .debug
        case .debug:
            .debug
        case .info:
            .info
        case .warning:
            .default
        case .error:
            .error
        }
    }
}

// MARK: - Thread Extension for TraceId

public extension Thread {
    /// 获取当前线程的 TraceId（扩展补充，避免重复定义）
    static var debugProbeTraceId: String? {
        Thread.current.threadDictionary["debugProbeTraceId"] as? String
    }

    /// 设置当前线程的 TraceId
    static func setDebugProbeTraceId(_ traceId: String?) {
        if let traceId {
            Thread.current.threadDictionary["debugProbeTraceId"] = traceId
        } else {
            Thread.current.threadDictionary.removeObject(forKey: "debugProbeTraceId")
        }
    }
}
