// DebugProbe.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

#if canImport(CocoaLumberjack)
    import CocoaLumberjack
#endif

/// Debug Probe 主入口，统一管理所有调试功能
public final class DebugProbe {
    // MARK: - Singleton

    public static let shared = DebugProbe()

    // MARK: - Configuration

    public struct Configuration {
        public let hubURL: URL
        public let token: String
        public var enableNetworkCapture: Bool = true
        public var enableLogCapture: Bool = true
        public var maxBufferSize: Int = 10000

        /// 网络捕获模式
        ///
        /// - `.automatic`（默认）: 自动拦截所有网络请求，无需修改业务代码
        /// - `.manual`: 需要手动将 protocolClasses 注入到 URLSessionConfiguration
        ///
        /// 自动模式通过 Swizzle URLSessionConfiguration 实现，对 Alamofire、
        /// 自定义 URLSession 等所有网络层都生效，是推荐的使用方式。
        public var networkCaptureMode: NetworkCaptureMode = .automatic

        /// 网络捕获范围
        ///
        /// - `.http`: 仅捕获 HTTP/HTTPS 请求
        /// - `.webSocket`: 仅捕获 WebSocket 连接
        /// - `.all`（默认）: 捕获所有网络活动
        ///
        /// WebSocket 捕获仅在 `.automatic` 模式下生效
        public var networkCaptureScope: NetworkCaptureScope = .all

        /// 是否启用事件持久化（断线时保存到本地，重连后恢复发送）
        public var enablePersistence: Bool = true

        /// 持久化队列最大大小
        public var maxPersistenceQueueSize: Int = 100_000

        /// 持久化事件最大保留天数
        public var persistenceRetentionDays: Int = 3

        public init(hubURL: URL, token: String) {
            self.hubURL = hubURL
            self.token = token
        }
    }

    // MARK: - Notifications

    /// 连接状态变化通知
    /// userInfo 包含 "state": ConnectionState
    public static let connectionStateDidChangeNotification = Notification.Name("DebugProbe.connectionStateDidChange")

    // MARK: - State

    public private(set) var isStarted: Bool = false
    public private(set) var configuration: Configuration?

    /// 当前连接状态（便捷访问）
    public var connectionState: DebugBridgeClient.ConnectionState {
        bridgeClient.state
    }

    // MARK: - Components

    public let eventBus = DebugEventBus.shared
    public let bridgeClient = DebugBridgeClient()
    public let mockRuleEngine = MockRuleEngine.shared

    #if canImport(CocoaLumberjack)
        private var ddLogger: DebugProbeDDLogger?
    #endif

    // MARK: - Lifecycle

    private init() {
        setupCallbacks()
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // Mock 规则更新回调
        bridgeClient.onMockRulesReceived = { [weak self] rules in
            self?.mockRuleEngine.updateRules(rules)
        }

        // 捕获开关回调
        bridgeClient.onCaptureToggled = { [weak self] network, log in
            self?.setNetworkCaptureEnabled(network)
            self?.setLogCaptureEnabled(log)
        }

        // 连接状态回调
        bridgeClient.onStateChanged = { [weak self] state in
            DebugLog.debug(.bridge, "State: \(state)")
            // 发送状态变化通知
            NotificationCenter.default.post(
                name: DebugProbe.connectionStateDidChangeNotification,
                object: self,
                userInfo: ["state": state]
            )
        }

        // 错误回调
        bridgeClient.onError = { error in
            DebugLog.error(.bridge, "Error: \(error)")
        }
    }

    // MARK: - Start / Stop

    /// 启动 Debug Probe
    public func start(configuration: Configuration) {
        guard !isStarted else {
            DebugLog.debug("Already started")
            return
        }

        self.configuration = configuration
        eventBus.maxBufferSize = configuration.maxBufferSize

        // 启动网络捕获
        if configuration.enableNetworkCapture {
            NetworkInstrumentation.shared.start(
                mode: configuration.networkCaptureMode,
                scope: configuration.networkCaptureScope
            )
        }

        // 启动日志捕获
        if configuration.enableLogCapture {
            startLogCapture()
        }

        // 配置 Bridge Client
        var bridgeConfig = DebugBridgeClient.Configuration(hubURL: configuration.hubURL, token: configuration.token)
        bridgeConfig.enablePersistence = configuration.enablePersistence

        // 配置持久化队列
        if configuration.enablePersistence {
            var persistenceConfig = EventPersistenceQueue.Configuration()
            persistenceConfig.maxQueueSize = configuration.maxPersistenceQueueSize
            persistenceConfig.maxRetentionSeconds = TimeInterval(configuration.persistenceRetentionDays * 24 * 3600)
            bridgeConfig.persistenceConfig = persistenceConfig
        }

        // 连接到 Debug Hub
        bridgeClient.connect(configuration: bridgeConfig)

        isStarted = true
        DebugLog.info("Started with hub: \(configuration.hubURL)")
        if configuration.enablePersistence {
            DebugLog.info(
                "Persistence enabled (max \(configuration.maxPersistenceQueueSize) events, \(configuration.persistenceRetentionDays) days)"
            )
        }
    }

    /// 停止 Debug Probe
    public func stop() {
        guard isStarted else { return }

        bridgeClient.disconnect()
        NetworkInstrumentation.shared.stop()
        stopLogCapture()
        eventBus.clear()

        isStarted = false
        DebugLog.info("Stopped")
    }

    /// 使用新的配置重新连接
    /// 用于运行时配置变更后重新连接到新的 DebugHub
    public func reconnect(hubURL: URL, token: String) {
        guard isStarted, var config = configuration else {
            DebugLog.debug("Not started, cannot reconnect")
            return
        }

        DebugLog.debug("Reconnecting to \(hubURL)...")

        // 断开当前连接
        bridgeClient.disconnect()

        // 更新配置
        let newConfig = Configuration(hubURL: hubURL, token: token)
        configuration = Configuration(
            hubURL: hubURL,
            token: token
        )

        // 重新连接
        var bridgeConfig = DebugBridgeClient.Configuration(hubURL: hubURL, token: token)
        bridgeConfig.enablePersistence = config.enablePersistence

        if config.enablePersistence {
            var persistenceConfig = EventPersistenceQueue.Configuration()
            persistenceConfig.maxQueueSize = config.maxPersistenceQueueSize
            persistenceConfig.maxRetentionSeconds = TimeInterval(config.persistenceRetentionDays * 24 * 3600)
            bridgeConfig.persistenceConfig = persistenceConfig
        }

        bridgeClient.connect(configuration: bridgeConfig)
        DebugLog.info("Reconnected to \(hubURL)")
    }

    // MARK: - Network Capture Control

    public func setNetworkCaptureEnabled(_ enabled: Bool) {
        if enabled {
            let mode = configuration?.networkCaptureMode ?? .automatic
            let scope = configuration?.networkCaptureScope ?? .all
            NetworkInstrumentation.shared.start(mode: mode, scope: scope)
        } else {
            NetworkInstrumentation.shared.stop()
        }
    }

    // MARK: - Log Capture Control

    public func setLogCaptureEnabled(_ enabled: Bool) {
        if enabled {
            startLogCapture()
        } else {
            stopLogCapture()
        }
    }

    private func startLogCapture() {
        #if canImport(CocoaLumberjack)
            if ddLogger == nil {
                ddLogger = DebugProbeDDLogger()
                DDLog.add(ddLogger!)
            }
        #endif
    }

    private func stopLogCapture() {
        #if canImport(CocoaLumberjack)
            if let logger = ddLogger {
                DDLog.remove(logger)
                ddLogger = nil
            }
        #endif
    }

    // MARK: - WebSocket Debug Hooks

    /// 设置 WebSocket 调试钩子的类型别名
    public typealias WSSessionCreatedHook = (_ sessionId: String, _ url: String, _ headers: [String: String]) -> Void
    public typealias WSSessionClosedHook = (_ sessionId: String, _ closeCode: Int?, _ reason: String?) -> Void
    public typealias WSMessageHook = (_ sessionId: String, _ data: Data) -> Void

    /// 获取用于注入到宿主 App 的 WebSocket 调试钩子
    ///
    /// 使用方式（在 AppDelegate/SceneDelegate 中）：
    /// ```swift
    /// #if !APPSTORE
    /// import DebugProbe
    ///
    /// // 在 setupDebugProbe() 中设置钩子
    /// let hooks = DebugProbe.shared.getWebSocketHooks()
    /// WebSocketDebugHooks.onSessionCreated = hooks.onSessionCreated
    /// WebSocketDebugHooks.onSessionClosed = hooks.onSessionClosed
    /// WebSocketDebugHooks.onMessageSent = hooks.onMessageSent
    /// WebSocketDebugHooks.onMessageReceived = hooks.onMessageReceived
    /// #endif
    /// ```
    public func getWebSocketHooks() -> (
        onSessionCreated: WSSessionCreatedHook,
        onSessionClosed: WSSessionClosedHook,
        onMessageSent: WSMessageHook,
        onMessageReceived: WSMessageHook
    ) {
        let onSessionCreated: WSSessionCreatedHook = { sessionId, url, headers in
            DebugLog.info(.webSocket, "Hook: Session created - \(url)")
            let session = WSEvent.Session(
                id: sessionId,
                url: url,
                requestHeaders: headers,
                subprotocols: []
            )
            let event = WSEvent(kind: .sessionCreated(session))
            DebugEventBus.shared.enqueue(.webSocket(event))
        }

        let onSessionClosed: WSSessionClosedHook = { sessionId, closeCode, reason in
            DebugLog.info(.webSocket, "Hook: Session closed - \(sessionId), code: \(closeCode ?? -1)")
            var session = WSEvent.Session(id: sessionId, url: "", requestHeaders: [:], subprotocols: [])
            session.disconnectTime = Date()
            session.closeCode = closeCode
            session.closeReason = reason
            let event = WSEvent(kind: .sessionClosed(session))
            DebugEventBus.shared.enqueue(.webSocket(event))
        }

        let onMessageSent: WSMessageHook = { sessionId, data in
            DebugLog.debug(.webSocket, "Hook: Message sent - \(sessionId), size: \(data.count)")
            let frame = WSEvent.Frame(
                sessionId: sessionId,
                direction: .send,
                opcode: .binary,
                payload: data,
                isMocked: false,
                mockRuleId: nil
            )
            let event = WSEvent(kind: .frame(frame))
            DebugEventBus.shared.enqueue(.webSocket(event))
        }

        let onMessageReceived: WSMessageHook = { sessionId, data in
            DebugLog.debug(.webSocket, "Hook: Message received - \(sessionId), size: \(data.count)")
            let frame = WSEvent.Frame(
                sessionId: sessionId,
                direction: .receive,
                opcode: .binary,
                payload: data,
                isMocked: false,
                mockRuleId: nil
            )
            let event = WSEvent(kind: .frame(frame))
            DebugEventBus.shared.enqueue(.webSocket(event))
        }

        return (onSessionCreated, onSessionClosed, onMessageSent, onMessageReceived)
    }

    // MARK: - Manual Event Submission

    /// 手动提交一个日志事件
    public func log(
        level: LogEvent.Level,
        message: String,
        subsystem: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let event = LogEvent(
            source: .osLog,
            level: level,
            subsystem: subsystem,
            category: category,
            thread: Thread.isMainThread ? "main" : Thread.current.description,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line,
            message: message,
            tags: tags,
            traceId: traceId
        )
        eventBus.enqueue(.log(event))
    }
}

// MARK: - Convenience Logging Methods

public extension DebugProbe {
    func debug(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        tags: [String] = [],
        traceId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, tags: tags, traceId: traceId, file: file, function: function, line: line)
    }
}
