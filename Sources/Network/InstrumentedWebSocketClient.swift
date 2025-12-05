// InstrumentedWebSocketClient.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - WebSocket Client Protocol

/// WebSocket 客户端协议
public protocol WebSocketClient: AnyObject {
    func connect()
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(text: String)
    func send(data: Data)

    var onConnected: (() -> Void)? { get set }
    var onDisconnected: ((Int?, String?) -> Void)? { get set }
    var onText: ((String) -> Void)? { get set }
    var onData: ((Data) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
}

// MARK: - Instrumented WebSocket Client

/// 带完整调试功能的 WebSocket 客户端实现
///
/// 此类提供完整的 WebSocket 消息级别监控，包括：
/// - ✅ 连接创建/关闭
/// - ✅ 每一帧的发送和接收
/// - ✅ Mock 规则支持（可修改发送/接收的数据）
///
/// ## 使用场景
/// 当需要完整的 WebSocket 调试能力时，使用此类替代原生的 `URLSessionWebSocketTask`。
///
/// ## 与 WebSocketInstrumentation 的区别
/// - `WebSocketInstrumentation`: 零侵入，但只能监控连接级别（无法监控消息内容）
/// - `InstrumentedWebSocketClient`: 需要显式使用，但提供完整的消息级别监控
///
/// ## 使用示例
/// ```swift
/// let client = InstrumentedWebSocketClient(
///     url: URL(string: "wss://example.com/ws")!,
///     headers: ["Authorization": "Bearer token"]
/// )
///
/// client.onConnected = { print("Connected") }
/// client.onText = { text in print("Received: \(text)") }
/// client.onDisconnected = { code, reason in print("Disconnected") }
///
/// client.connect()
/// client.send(text: "Hello")
/// ```
public final class InstrumentedWebSocketClient: NSObject, WebSocketClient {
    // MARK: - Properties

    private let url: URL
    private let headers: [String: String]
    private let subprotocols: [String]

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionId: String = ""
    private var session: WSEvent.Session?

    // MARK: - Callbacks

    public var onConnected: (() -> Void)?
    public var onDisconnected: ((Int?, String?) -> Void)?
    public var onText: ((String) -> Void)?
    public var onData: ((Data) -> Void)?
    public var onError: ((Error) -> Void)?

    // MARK: - Lifecycle

    public init(url: URL, headers: [String: String] = [:], subprotocols: [String] = []) {
        self.url = url
        self.headers = headers
        self.subprotocols = subprotocols
        super.init()
    }

    deinit {
        disconnect(closeCode: .goingAway, reason: nil)
    }

    // MARK: - WebSocketClient Implementation

    public func connect() {
        sessionId = UUID().uuidString

        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 如果有 subprotocols，通过 Sec-WebSocket-Protocol header 设置
        if !subprotocols.isEmpty {
            request.setValue(subprotocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // 使用 URLRequest 版本，subprotocols 已通过 header 设置
        webSocketTask = urlSession?.webSocketTask(with: request)

        webSocketTask?.resume()

        // 记录会话创建事件（立即记录，不等待连接成功）
        session = WSEvent.Session(
            id: sessionId,
            url: url.absoluteString,
            requestHeaders: headers,
            subprotocols: subprotocols
        )
        // 立即发送 sessionCreated 事件，让 WebUI 可以显示会话
        // 即使连接最终失败，也会有一个会话记录
        recordSessionCreated()

        receiveNextMessage()
    }

    public func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        webSocketTask?.cancel(with: closeCode, reason: reason)
        recordSessionClosed(
            closeCode: Int(closeCode.rawValue),
            reason: reason.flatMap { String(data: $0, encoding: .utf8) }
        )
        cleanup()
    }

    public func send(text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        sendMessage(message, payload: Data(text.utf8), opcode: .text)
    }

    public func send(data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        sendMessage(message, payload: data, opcode: .binary)
    }

    // MARK: - Internal Methods

    private func sendMessage(_ message: URLSessionWebSocketTask.Message, payload: Data, opcode: WSEvent.Frame.Opcode) {
        // 过 Mock 规则引擎
        let (modifiedPayload, isMocked, ruleId) = MockRuleEngine.shared.processWSOutgoingFrame(
            payload,
            sessionId: sessionId,
            sessionURL: url.absoluteString
        )

        // 记录发送帧事件
        recordFrame(
            direction: .send,
            opcode: opcode,
            payload: modifiedPayload,
            isMocked: isMocked,
            mockRuleId: ruleId
        )

        // 发送修改后的消息
        let actualMessage: URLSessionWebSocketTask.Message = switch opcode {
        case .text:
            .string(String(data: modifiedPayload, encoding: .utf8) ?? "")
        case .binary:
            .data(modifiedPayload)
        default:
            message
        }

        webSocketTask?.send(actualMessage) { [weak self] error in
            if let error {
                self?.onError?(error)
            }
        }
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(message):
                handleReceivedMessage(message)
                receiveNextMessage()

            case let .failure(error):
                onError?(error)
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let payload: Data
        let opcode: WSEvent.Frame.Opcode

        switch message {
        case let .string(text):
            payload = Data(text.utf8)
            opcode = .text
        case let .data(data):
            payload = data
            opcode = .binary
        @unknown default:
            return
        }

        // 过 Mock 规则引擎
        let (modifiedPayload, isMocked, ruleId) = MockRuleEngine.shared.processWSIncomingFrame(
            payload,
            sessionId: sessionId,
            sessionURL: url.absoluteString
        )

        // 记录接收帧事件
        recordFrame(
            direction: .receive,
            opcode: opcode,
            payload: modifiedPayload,
            isMocked: isMocked,
            mockRuleId: ruleId
        )

        // 回调业务层（使用修改后的数据）
        switch opcode {
        case .text:
            if let text = String(data: modifiedPayload, encoding: .utf8) {
                onText?(text)
            }
        case .binary:
            onData?(modifiedPayload)
        default:
            break
        }
    }

    private func cleanup() {
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: - Event Recording

    private func recordSessionCreated() {
        guard let session else { return }
        let event = WSEvent(kind: .sessionCreated(session))
        DebugEventBus.shared.enqueue(.webSocket(event))
    }

    private func recordSessionClosed(closeCode: Int?, reason: String?) {
        guard var session else { return }
        session.disconnectTime = Date()
        session.closeCode = closeCode
        session.closeReason = reason
        self.session = session

        let event = WSEvent(kind: .sessionClosed(session))
        DebugEventBus.shared.enqueue(.webSocket(event))
    }

    private func recordFrame(
        direction: WSEvent.Frame.Direction,
        opcode: WSEvent.Frame.Opcode,
        payload: Data,
        isMocked: Bool,
        mockRuleId: String?
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
}

// MARK: - URLSessionWebSocketDelegate

extension InstrumentedWebSocketClient: URLSessionWebSocketDelegate {
    public func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didOpenWithProtocol _: String?
    ) {
        // sessionCreated 已在 connect() 中发送，这里只触发回调
        onConnected?()
    }

    public func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        recordSessionClosed(closeCode: Int(closeCode.rawValue), reason: reasonString)
        onDisconnected?(Int(closeCode.rawValue), reasonString)
    }
}
