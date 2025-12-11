// WebUIPluginState.swift
// DebugProbe
//
// Created by Sun on 2025/12/13.
// 管理来自 WebUI 的插件启用状态

import Foundation

// MARK: - WebUI 插件状态

/// WebUI 插件状态数据结构
public struct WebUIPluginState: Codable, Sendable, Identifiable {
    /// 插件 ID
    public let pluginId: String
    /// 插件显示名称
    public let displayName: String
    /// 是否启用
    public let isEnabled: Bool

    public var id: String { pluginId }

    public init(pluginId: String, displayName: String, isEnabled: Bool) {
        self.pluginId = pluginId
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

// MARK: - WebUI 插件状态管理器

/// 管理从 DebugHub 同步过来的 WebUI 插件状态
/// 线程安全的单例，存储 WebUI 中各插件的启用/禁用状态
public final class WebUIPluginStateManager: @unchecked Sendable {
    /// 单例
    public static let shared = WebUIPluginStateManager()

    /// 插件状态变化通知
    public static let stateDidChangeNotification = Notification.Name("WebUIPluginStateManager.stateDidChange")

    /// 存储插件状态
    private var states: [String: WebUIPluginState] = [:]

    /// 线程安全锁
    private let lock = NSLock()

    private init() {}

    // MARK: - Public Methods

    /// 更新插件状态列表
    /// - Parameter newStates: 新的状态列表
    public func updateStates(_ newStates: [WebUIPluginState]) {
        lock.lock()
        for state in newStates {
            states[state.pluginId] = state
        }
        lock.unlock()

        DebugLog.info(.plugin, "WebUI plugin states updated: \(newStates.count) plugins")

        // 发送通知（在主线程）
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
        }
    }

    /// 获取所有插件状态
    /// - Returns: 所有 WebUI 插件状态列表
    public func getAllStates() -> [WebUIPluginState] {
        lock.lock()
        defer { lock.unlock() }
        return Array(states.values).sorted { $0.pluginId < $1.pluginId }
    }

    /// 获取指定插件状态
    /// - Parameter pluginId: 插件 ID
    /// - Returns: 插件状态，如果不存在则返回 nil
    public func getState(for pluginId: String) -> WebUIPluginState? {
        lock.lock()
        defer { lock.unlock() }
        return states[pluginId]
    }

    /// 检查插件是否启用
    /// - Parameter pluginId: 插件 ID
    /// - Returns: 是否启用，如果状态未知则默认返回 true
    public func isPluginEnabled(_ pluginId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return states[pluginId]?.isEnabled ?? true
    }

    /// 清除所有状态
    public func clearStates() {
        lock.lock()
        defer { lock.unlock() }
        states.removeAll()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
        }
    }
}
