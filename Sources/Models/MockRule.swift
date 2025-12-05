// MockRule.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

/// Mock 规则模型，用于配置请求/响应的拦截和修改
public struct MockRule: Codable, Identifiable {
    public enum TargetType: String, Codable, CaseIterable {
        case httpRequest
        case httpResponse
        case wsOutgoing
        case wsIncoming
    }

    public struct Condition: Codable {
        public var urlPattern: String?
        public var method: String?
        public var statusCode: Int?
        public var headerContains: [String: String]?
        public var bodyContains: String?
        public var wsPayloadContains: String?
        public var enabled: Bool

        public init(
            urlPattern: String? = nil,
            method: String? = nil,
            statusCode: Int? = nil,
            headerContains: [String: String]? = nil,
            bodyContains: String? = nil,
            wsPayloadContains: String? = nil,
            enabled: Bool = true
        ) {
            self.urlPattern = urlPattern
            self.method = method
            self.statusCode = statusCode
            self.headerContains = headerContains
            self.bodyContains = bodyContains
            self.wsPayloadContains = wsPayloadContains
            self.enabled = enabled
        }

        /// 检查 HTTP 请求是否匹配条件
        public func matches(request: HTTPEvent.Request) -> Bool {
            guard enabled else { return false }

            // URL 匹配
            if let pattern = urlPattern, !pattern.isEmpty {
                if !matchesPattern(pattern, text: request.url) {
                    return false
                }
            }

            // 方法匹配
            if let method, !method.isEmpty {
                if request.method.uppercased() != method.uppercased() {
                    return false
                }
            }

            // Header 匹配
            if let headerContains {
                for (key, value) in headerContains {
                    guard
                        let headerValue = request.headers[key],
                        headerValue.contains(value) else {
                        return false
                    }
                }
            }

            // Body 匹配
            if let bodyContains, !bodyContains.isEmpty {
                guard
                    let body = request.body,
                    let bodyString = String(data: body, encoding: .utf8),
                    bodyString.contains(bodyContains) else {
                    return false
                }
            }

            return true
        }

        /// 检查 HTTP 响应是否匹配条件
        public func matches(response: HTTPEvent.Response, request: HTTPEvent.Request) -> Bool {
            guard enabled else { return false }

            // 先检查请求条件
            if let pattern = urlPattern, !pattern.isEmpty {
                if !matchesPattern(pattern, text: request.url) {
                    return false
                }
            }

            if let method, !method.isEmpty {
                if request.method.uppercased() != method.uppercased() {
                    return false
                }
            }

            // 状态码匹配
            if let statusCode {
                if response.statusCode != statusCode {
                    return false
                }
            }

            return true
        }

        /// 检查 WebSocket 帧是否匹配条件
        public func matches(frame: WSEvent.Frame, sessionURL: String) -> Bool {
            guard enabled else { return false }

            // URL 匹配
            if let pattern = urlPattern, !pattern.isEmpty {
                if !matchesPattern(pattern, text: sessionURL) {
                    return false
                }
            }

            // Payload 匹配
            if let wsPayloadContains, !wsPayloadContains.isEmpty {
                guard
                    let payloadString = String(data: frame.payload, encoding: .utf8),
                    payloadString.contains(wsPayloadContains) else {
                    return false
                }
            }

            return true
        }

        private func matchesPattern(_ pattern: String, text: String) -> Bool {
            // 支持简单的通配符匹配和前缀匹配
            if pattern.hasPrefix("^") || pattern.hasSuffix("$") {
                // 正则表达式匹配
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    return regex.firstMatch(in: text, options: [], range: range) != nil
                }
                return false
            } else if pattern.contains("*") {
                // 通配符匹配
                let regexPattern = pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    return regex.firstMatch(in: text, options: [], range: range) != nil
                }
                return false
            } else {
                // 前缀匹配或包含匹配
                return text.contains(pattern)
            }
        }
    }

    public struct Action: Codable {
        // HTTP 请求修改
        public var modifyRequestHeaders: [String: String]?
        public var modifyRequestBody: Data?

        // HTTP 响应 Mock
        public var mockResponseStatusCode: Int?
        public var mockResponseHeaders: [String: String]?
        public var mockResponseBody: Data?

        // WebSocket 帧修改
        public var mockWebSocketPayload: Data?

        // 延迟（毫秒）
        public var delayMilliseconds: Int?

        public init(
            modifyRequestHeaders: [String: String]? = nil,
            modifyRequestBody: Data? = nil,
            mockResponseStatusCode: Int? = nil,
            mockResponseHeaders: [String: String]? = nil,
            mockResponseBody: Data? = nil,
            mockWebSocketPayload: Data? = nil,
            delayMilliseconds: Int? = nil
        ) {
            self.modifyRequestHeaders = modifyRequestHeaders
            self.modifyRequestBody = modifyRequestBody
            self.mockResponseStatusCode = mockResponseStatusCode
            self.mockResponseHeaders = mockResponseHeaders
            self.mockResponseBody = mockResponseBody
            self.mockWebSocketPayload = mockWebSocketPayload
            self.delayMilliseconds = delayMilliseconds
        }
    }

    public let id: String
    public var name: String
    public var targetType: TargetType
    public var condition: Condition
    public var action: Action
    public var priority: Int
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        targetType: TargetType,
        condition: Condition,
        action: Action,
        priority: Int = 0,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.targetType = targetType
        self.condition = condition
        self.action = action
        self.priority = priority
        self.enabled = enabled
    }
}
