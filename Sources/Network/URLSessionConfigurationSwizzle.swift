// URLSessionConfigurationSwizzle.swift
// DebugPlatform
//
// Created by Sun on 2025/12/03.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - URLSessionConfiguration Swizzle

/// 通过 Method Swizzling 自动将 CaptureURLProtocol 注入到所有 URLSessionConfiguration 中
/// 这样可以实现零侵入的网络拦截，无需修改任何业务代码
enum URLSessionConfigurationSwizzle {
    // MARK: - State

    private(set) static var isSwizzled = false
    private static let lock = NSLock()

    // MARK: - Public API

    /// 启用自动注入
    /// 调用后，所有通过 `.default` 或 `.ephemeral` 创建的 URLSessionConfiguration
    /// 都会自动包含 CaptureURLProtocol
    static func enable() {
        lock.lock()
        defer { lock.unlock() }

        guard !isSwizzled else { return }

        swizzleDefaultConfiguration()
        swizzleEphemeralConfiguration()

        isSwizzled = true
        DebugLog.info(.network, "URLSessionConfiguration swizzle enabled - all network requests will be captured")
    }

    /// 禁用自动注入
    /// 注意：已经创建的 URLSession 不受影响
    static func disable() {
        lock.lock()
        defer { lock.unlock() }

        guard isSwizzled else { return }

        // 再次 swizzle 会恢复原始实现
        swizzleDefaultConfiguration()
        swizzleEphemeralConfiguration()

        isSwizzled = false
        DebugLog.info(.network, "URLSessionConfiguration swizzle disabled")
    }

    /// 获取干净的 .default configuration（不包含 CaptureURLProtocol）
    /// 用于 CaptureURLProtocol 内部创建 URLSession，避免循环
    static func cleanDefaultConfiguration() -> URLSessionConfiguration {
        if isSwizzled {
            // swizzle 后，swizzled_default 指向原始的 .default 实现
            return URLSessionConfiguration.swizzled_default
        }
        return URLSessionConfiguration.default
    }

    // MARK: - Private

    private static func swizzleDefaultConfiguration() {
        let originalSelector = #selector(getter: URLSessionConfiguration.default)
        let swizzledSelector = #selector(getter: URLSessionConfiguration.swizzled_default)

        guard
            let originalMethod = class_getClassMethod(URLSessionConfiguration.self, originalSelector),
            let swizzledMethod = class_getClassMethod(URLSessionConfiguration.self, swizzledSelector)
        else {
            DebugLog.error(.network, "Failed to swizzle URLSessionConfiguration.default")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    private static func swizzleEphemeralConfiguration() {
        let originalSelector = #selector(getter: URLSessionConfiguration.ephemeral)
        let swizzledSelector = #selector(getter: URLSessionConfiguration.swizzled_ephemeral)

        guard
            let originalMethod = class_getClassMethod(URLSessionConfiguration.self, originalSelector),
            let swizzledMethod = class_getClassMethod(URLSessionConfiguration.self, swizzledSelector)
        else {
            DebugLog.error(.network, "Failed to swizzle URLSessionConfiguration.ephemeral")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - URLSessionConfiguration Extension

extension URLSessionConfiguration {
    /// Swizzled default configuration getter
    @objc dynamic class var swizzled_default: URLSessionConfiguration {
        // 调用原始实现（因为已经 swizzle，所以这里实际调用的是原始的 .default）
        let configuration = swizzled_default
        injectCaptureProtocol(into: configuration)
        return configuration
    }

    /// Swizzled ephemeral configuration getter
    @objc dynamic class var swizzled_ephemeral: URLSessionConfiguration {
        // 调用原始实现
        let configuration = swizzled_ephemeral
        injectCaptureProtocol(into: configuration)
        return configuration
    }

    /// 将 CaptureURLProtocol 注入到 configuration 中
    private static func injectCaptureProtocol(into configuration: URLSessionConfiguration) {
        var protocols = configuration.protocolClasses ?? []

        // 检查是否已经注入，避免重复
        if !protocols.contains(where: { $0 == CaptureURLProtocol.self }) {
            protocols.insert(CaptureURLProtocol.self, at: 0)
            configuration.protocolClasses = protocols
        }
    }
}
