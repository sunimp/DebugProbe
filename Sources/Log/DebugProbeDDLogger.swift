// DebugProbeDDLogger.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

#if canImport(CocoaLumberjack)
    import CocoaLumberjack
    import Foundation

    /// CocoaLumberjack 自定义 Logger，用于将日志转发到 DebugEventBus
    public final class DebugProbeDDLogger: DDAbstractLogger {
        // MARK: - Properties

        private var _logFormatter: DDLogFormatter?

        // MARK: - Lifecycle

        override public init() {
            super.init()
        }

        // MARK: - DDAbstractLogger Override

        override public var logFormatter: DDLogFormatter? {
            get { _logFormatter }
            set { _logFormatter = newValue }
        }

        override public func log(message logMessage: DDLogMessage) {
            // 将 DDLogMessage 映射为 LogEvent
            let loggerName = (logMessage.representedObject as? String) ?? String(describing: logMessage.representedObject)

            let event = LogEvent(
                id: UUID().uuidString,
                source: .cocoaLumberjack,
                timestamp: logMessage.timestamp,
                level: mapDDLogFlagToLevel(logMessage.flag),
                subsystem: nil,
                category: logMessage.context == 0 ? nil : String(logMessage.context),
                loggerName: logMessage.representedObject != nil ? loggerName : nil,
                thread: logMessage.threadID,
                file: logMessage.fileName,
                function: logMessage.function,
                line: Int(logMessage.line),
                message: logMessage.message,
                tags: extractTags(from: logMessage),
                traceId: extractTraceId(from: logMessage)
            )

            DebugEventBus.shared.enqueue(.log(event))
        }

        // MARK: - Helpers

        /// 将 DDLogFlag 映射为 LogEvent.Level
        /// CocoaLumberjack DDLogFlag: verbose, debug, info, warning, error
        private func mapDDLogFlagToLevel(_ flag: DDLogFlag) -> LogEvent.Level {
            switch flag {
            case .verbose:
                .verbose
            case .debug:
                .debug
            case .info:
                .info
            case .warning:
                .warning
            case .error:
                .error
            default:
                .debug
            }
        }

        /// 从 DDLogMessage 提取自定义标签
        private func extractTags(from message: DDLogMessage) -> [String] {
            var tags: [String] = []

            // 从 representedObject 字段提取（替代已废弃的 tag）
            if let tagString = message.representedObject as? String {
                tags.append(tagString)
            }

            return tags
        }

        /// 从 DDLogMessage 提取 traceId
        private func extractTraceId(from _: DDLogMessage) -> String? {
            // 可以从 Thread-local storage 或其他地方获取 traceId
            // 这里提供一个扩展点
            Thread.current.threadDictionary["debugProbeTraceId"] as? String
        }
    }

#endif
