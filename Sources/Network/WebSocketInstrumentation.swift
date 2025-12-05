// WebSocketInstrumentation.swift
// DebugPlatform
//
// Created by Sun on 2025/12/03.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation
import ObjectiveC

// MARK: - WebSocket Instrumentation

/// WebSocket 连接级别监控
///
/// 通过 Swizzle URLSession 的 webSocketTask 方法，自动监控 WebSocket 连接的创建。
///
/// ## 限制
/// 由于 `URLSessionWebSocketTask.Message` 是 Swift-only 类型，无法通过 Swizzle
/// 拦截 `send` 和 `receive` 方法。因此此类只能监控：
/// - 连接创建
/// - 连接关闭（通过 cancel 方法）
///
/// 如需完整的消息级别监控（包括每一帧的发送和接收），请使用 `InstrumentedWebSocketClient`。
public final class WebSocketInstrumentation {
    // MARK: - Singleton

    public static let shared = WebSocketInstrumentation()

    // MARK: - State

    private static var isSwizzled = false
    private static let lock = NSLock()

    /// 活跃的 WebSocket 会话 (taskIdentifier -> SessionInfo)
    private var activeSessions: [Int: WebSocketSessionInfo] = [:]
    private let sessionsLock = NSLock()

    public private(set) var isEnabled = false

    // MARK: - Lifecycle

    private init() {}

    // MARK: - Public API

    /// 启用 WebSocket 连接监控
    ///
    /// 监控范围：
    /// - ✅ 连接创建（webSocketTask 调用）
    /// - ✅ 连接关闭（cancel 调用）
    /// - ❌ 消息发送/接收（Swift-only 类型，无法 Swizzle）
    ///
    /// 如需消息级别监控，请使用 `InstrumentedWebSocketClient`
    public func start() {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        guard !Self.isSwizzled else { return }

        swizzleWebSocketTaskCreation()

        Self.isSwizzled = true
        isEnabled = true
        DebugLog.info(.webSocket, "Instrumentation enabled - connection-level monitoring active")
        DebugLog.info(.webSocket, "Note: For message-level monitoring, use InstrumentedWebSocketClient")
    }

    /// 停止 WebSocket 监控
    public func stop() {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        guard Self.isSwizzled else { return }

        // 再次 swizzle 恢复原始实现
        swizzleWebSocketTaskCreation()

        Self.isSwizzled = false
        isEnabled = false
        DebugLog.info(.webSocket, "Instrumentation disabled")
    }

    // MARK: - Session Management

    func registerSession(task: URLSessionWebSocketTask, url: URL, headers: [String: String]) {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }

        let sessionId = UUID().uuidString
        let info = WebSocketSessionInfo(
            sessionId: sessionId,
            taskIdentifier: task.taskIdentifier,
            url: url,
            headers: headers,
            connectTime: Date()
        )
        activeSessions[task.taskIdentifier] = info

        // 记录会话创建事件
        let session = WSEvent.Session(
            id: sessionId,
            url: url.absoluteString,
            requestHeaders: headers,
            subprotocols: []
        )
        let event = WSEvent(kind: .sessionCreated(session))
        DebugEventBus.shared.enqueue(.webSocket(event))

        DebugLog.debug(.webSocket, "Connection created: \(url.absoluteString)")
    }

    func getSessionInfo(for taskIdentifier: Int) -> (sessionId: String, url: URL)? {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }

        guard let info = activeSessions[taskIdentifier] else { return nil }
        return (info.sessionId, info.url)
    }

    func recordSessionClosed(taskIdentifier: Int, closeCode: Int?, reason: String?) {
        sessionsLock.lock()
        guard let info = activeSessions.removeValue(forKey: taskIdentifier) else {
            sessionsLock.unlock()
            return
        }
        sessionsLock.unlock()

        var session = WSEvent.Session(
            id: info.sessionId,
            url: info.url.absoluteString,
            requestHeaders: info.headers,
            subprotocols: []
        )
        session.disconnectTime = Date()
        session.closeCode = closeCode
        session.closeReason = reason

        let event = WSEvent(kind: .sessionClosed(session))
        DebugEventBus.shared.enqueue(.webSocket(event))

        DebugLog.debug(.webSocket, "Connection closed: \(info.url.absoluteString), code: \(closeCode ?? -1)")
    }

    // MARK: - Manual Frame Recording (for InstrumentedWebSocketClient)

    /// 手动记录 WebSocket 帧（供 InstrumentedWebSocketClient 使用）
    public func recordFrame(
        sessionId: String,
        sessionURL: String,
        direction: WSEvent.Frame.Direction,
        opcode: WSEvent.Frame.Opcode,
        payload: Data,
        isMocked: Bool = false,
        mockRuleId: String? = nil
    ) {
        let frame = WSEvent.Frame(
            sessionId: sessionId,
            direction: direction,
            opcode: opcode,
            payload: payload,
            isMocked: isMocked,
            mockRuleId: mockRuleId
        )

        let event = WSEvent(kind: .frame(frame))
        DebugEventBus.shared.enqueue(.webSocket(event))
    }

    // MARK: - Private - Swizzle

    private func swizzleWebSocketTaskCreation() {
        // Swizzle URLSession.webSocketTask(with: URL)
        swizzleMethod(
            cls: URLSession.self,
            original: #selector(URLSession.webSocketTask(with:) as (URLSession) -> (URL) -> URLSessionWebSocketTask),
            swizzled: #selector(URLSession.debugProbe_webSocketTask(with:))
        )

        // Swizzle URLSession.webSocketTask(with: URLRequest)
        swizzleMethod(
            cls: URLSession.self,
            original: #selector(URLSession
                .webSocketTask(with:) as (URLSession) -> (URLRequest) -> URLSessionWebSocketTask),
            swizzled: #selector(URLSession.debugProbe_webSocketTask(withRequest:))
        )

        // Swizzle URLSessionWebSocketTask.cancel(with:reason:)
        swizzleMethod(
            cls: URLSessionWebSocketTask.self,
            original: #selector(URLSessionWebSocketTask.cancel(with:reason:)),
            swizzled: #selector(URLSessionWebSocketTask.debugProbe_cancel(with:reason:))
        )
    }

    private func swizzleMethod(cls: AnyClass, original: Selector, swizzled: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(cls, original),
            let swizzledMethod = class_getInstanceMethod(cls, swizzled)
        else {
            DebugLog.error(.webSocket, "Failed to swizzle \(cls).\(original)")
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - Session Info

private struct WebSocketSessionInfo {
    let sessionId: String
    let taskIdentifier: Int
    let url: URL
    let headers: [String: String]
    let connectTime: Date
}

// MARK: - URLSession Extension

extension URLSession {
    @objc dynamic func debugProbe_webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        let task = debugProbe_webSocketTask(with: url) // 调用原始实现

        // 排除 DebugProbe 自己的 debug-bridge 连接
        if !url.absoluteString.contains("debug-bridge") {
            WebSocketInstrumentation.shared.registerSession(task: task, url: url, headers: [:])
        }

        return task
    }

    @objc dynamic func debugProbe_webSocketTask(withRequest request: URLRequest) -> URLSessionWebSocketTask {
        let task = debugProbe_webSocketTask(withRequest: request) // 调用原始实现

        if let url = request.url {
            // 排除 DebugProbe 自己的 debug-bridge 连接
            if !url.absoluteString.contains("debug-bridge") {
                let headers = request.allHTTPHeaderFields ?? [:]
                WebSocketInstrumentation.shared.registerSession(task: task, url: url, headers: headers)
            }
        }

        return task
    }
}

// MARK: - URLSessionWebSocketTask Extension

extension URLSessionWebSocketTask {
    @objc dynamic func debugProbe_cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // 记录关闭事件
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        WebSocketInstrumentation.shared.recordSessionClosed(
            taskIdentifier: taskIdentifier,
            closeCode: Int(closeCode.rawValue),
            reason: reasonString
        )

        // 调用原始实现
        debugProbe_cancel(with: closeCode, reason: reason)
    }
}
