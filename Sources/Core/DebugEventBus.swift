// DebugEventBus.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

/// 调试事件分发中心，负责管理本地事件缓冲和分发
public final class DebugEventBus {
    // MARK: - Singleton

    public static let shared = DebugEventBus()

    // MARK: - Configuration

    /// 本地缓冲区最大容量
    public var maxBufferSize: Int = 10000

    /// 事件丢弃策略
    public enum DropPolicy {
        case dropOldest // 丢弃最旧的事件
        case dropNewest // 丢弃最新的事件
        case sample(rate: Double) // 采样保留
    }

    public var dropPolicy: DropPolicy = .dropOldest

    // MARK: - State

    private var eventBuffer: [DebugEvent] = []
    private let bufferQueue = DispatchQueue(label: "com.sunimp.debugplatform.eventbus", qos: .utility)
    private var subscribers: [String: (DebugEvent) -> Void] = [:]
    private let subscriberLock = NSLock()

    // MARK: - Lifecycle

    private init() {}

    // MARK: - Event Ingestion

    /// 入队一个调试事件
    public func enqueue(_ event: DebugEvent) {
        bufferQueue.async { [weak self] in
            self?.internalEnqueue(event)
        }
    }

    /// 批量入队事件
    public func enqueue(_ events: [DebugEvent]) {
        bufferQueue.async { [weak self] in
            for event in events {
                self?.internalEnqueue(event)
            }
        }
    }

    private func internalEnqueue(_ event: DebugEvent) {
        // 检查缓冲区是否已满
        if eventBuffer.count >= maxBufferSize {
            switch dropPolicy {
            case .dropOldest:
                eventBuffer.removeFirst()
            case .dropNewest:
                return // 不添加新事件
            case let .sample(rate):
                // rate 表示保留率：rate=0.8 意味着保留 80% 的事件
                // 当随机数 > rate 时丢弃，确保 higher rate → 保留更多事件
                if Double.random(in: 0...1) > rate {
                    return // 不满足采样条件，丢弃此事件
                }
                if eventBuffer.count >= maxBufferSize {
                    eventBuffer.removeFirst()
                }
            }
        }

        eventBuffer.append(event)

        // 打印事件入队日志（便于调试）
        switch event {
        case let .http(httpEvent):
            DebugLog.debug(
                .eventBus,
                "HTTP event: \(httpEvent.request.method) \(httpEvent.request.url.prefix(80))... (buffer: \(eventBuffer.count))"
            )
        case let .log(logEvent):
            DebugLog.debug(
                .eventBus,
                "Log event: [\(logEvent.level)] \(logEvent.message.prefix(50))... (buffer: \(eventBuffer.count))"
            )
        case let .webSocket(wsEvent):
            DebugLog.debug(.eventBus, "WebSocket event: \(wsEvent) (buffer: \(eventBuffer.count))")
        case .stats:
            DebugLog.debug(.eventBus, "Stats event (buffer: \(eventBuffer.count))")
        }

        // 通知订阅者
        notifySubscribers(event)
    }

    // MARK: - Event Retrieval

    /// 获取并清空待发送的事件
    public func dequeueAll() -> [DebugEvent] {
        var result: [DebugEvent] = []
        bufferQueue.sync {
            result = eventBuffer
            eventBuffer.removeAll()
        }
        return result
    }

    /// 获取指定数量的事件（不清空）
    public func peek(count: Int) -> [DebugEvent] {
        var result: [DebugEvent] = []
        bufferQueue.sync {
            result = Array(eventBuffer.prefix(count))
        }
        return result
    }

    /// 移除指定数量的已处理事件
    public func removeFirst(_ count: Int) {
        bufferQueue.async { [weak self] in
            guard let self else { return }
            let removeCount = min(count, eventBuffer.count)
            eventBuffer.removeFirst(removeCount)
        }
    }

    /// 获取当前缓冲区大小
    public var bufferCount: Int {
        var count = 0
        bufferQueue.sync {
            count = eventBuffer.count
        }
        return count
    }

    // MARK: - Subscription

    /// 订阅事件流
    @discardableResult
    public func subscribe(id: String = UUID().uuidString, handler: @escaping (DebugEvent) -> Void) -> String {
        subscriberLock.lock()
        defer { subscriberLock.unlock() }
        subscribers[id] = handler
        return id
    }

    /// 取消订阅
    public func unsubscribe(id: String) {
        subscriberLock.lock()
        defer { subscriberLock.unlock() }
        subscribers.removeValue(forKey: id)
    }

    private func notifySubscribers(_ event: DebugEvent) {
        subscriberLock.lock()
        let currentSubscribers = subscribers
        subscriberLock.unlock()

        for (_, handler) in currentSubscribers {
            handler(event)
        }
    }

    // MARK: - Cleanup

    /// 清空所有事件
    public func clear() {
        bufferQueue.async { [weak self] in
            self?.eventBuffer.removeAll()
        }
    }
}
