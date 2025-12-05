// BreakpointRule.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - 断点规则

/// 断点规则，用于拦截请求/响应并等待手动操作
public struct BreakpointRule: Codable, Identifiable {
    public let id: String
    public var name: String
    public var urlPattern: String?
    public var method: String?
    public var phase: BreakpointPhase
    public var enabled: Bool
    public var priority: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        urlPattern: String? = nil,
        method: String? = nil,
        phase: BreakpointPhase = .request,
        enabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.method = method
        self.phase = phase
        self.enabled = enabled
        self.priority = priority
    }
}

// MARK: - 断点阶段

public enum BreakpointPhase: String, Codable {
    case request // 拦截请求（发送前）
    case response // 拦截响应（返回前）
    case both // 两者都拦截
}

// MARK: - 断点命中事件

public struct BreakpointHit: Codable {
    public let breakpointId: String
    public let requestId: String
    public let phase: BreakpointPhase
    public let timestamp: Date
    public let request: BreakpointRequestSnapshot
    public let response: BreakpointResponseSnapshot?

    public init(
        breakpointId: String,
        requestId: String,
        phase: BreakpointPhase,
        timestamp: Date = Date(),
        request: BreakpointRequestSnapshot,
        response: BreakpointResponseSnapshot? = nil
    ) {
        self.breakpointId = breakpointId
        self.requestId = requestId
        self.phase = phase
        self.timestamp = timestamp
        self.request = request
        self.response = response
    }
}

// MARK: - 请求快照

public struct BreakpointRequestSnapshot: Codable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?

    public init(
        method: String,
        url: String,
        headers: [String: String],
        body: Data? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public init(from request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = request.url?.absoluteString ?? ""
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody
    }

    public func toURLRequest() -> URLRequest? {
        guard let requestURL = URL(string: url) else { return nil }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        return request
    }
}

// MARK: - 响应快照

public struct BreakpointResponseSnapshot: Codable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data?

    public init(
        statusCode: Int,
        headers: [String: String],
        body: Data? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

// MARK: - 断点操作指令

public enum BreakpointAction: Codable {
    case resume // 继续执行原始请求/响应
    case modify(BreakpointModification) // 使用修改后的数据继续
    case abort // 中止请求
    case mockResponse(BreakpointResponseSnapshot) // 直接返回 Mock 响应

    private enum CodingKeys: String, CodingKey {
        case type
        case modification
        case mockResponse
    }

    private enum ActionType: String, Codable {
        case resume
        case modify
        case abort
        case mockResponse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .resume:
            self = .resume
        case .modify:
            let modification = try container.decode(BreakpointModification.self, forKey: .modification)
            self = .modify(modification)
        case .abort:
            self = .abort
        case .mockResponse:
            let response = try container.decode(BreakpointResponseSnapshot.self, forKey: .mockResponse)
            self = .mockResponse(response)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .resume:
            try container.encode(ActionType.resume, forKey: .type)
        case let .modify(modification):
            try container.encode(ActionType.modify, forKey: .type)
            try container.encode(modification, forKey: .modification)
        case .abort:
            try container.encode(ActionType.abort, forKey: .type)
        case let .mockResponse(response):
            try container.encode(ActionType.mockResponse, forKey: .type)
            try container.encode(response, forKey: .mockResponse)
        }
    }
}

// MARK: - 断点修改内容

public struct BreakpointModification: Codable {
    public var request: BreakpointRequestSnapshot?
    public var response: BreakpointResponseSnapshot?

    public init(
        request: BreakpointRequestSnapshot? = nil,
        response: BreakpointResponseSnapshot? = nil
    ) {
        self.request = request
        self.response = response
    }
}

// MARK: - 断点恢复指令

public struct BreakpointResume: Codable {
    public let requestId: String
    public let action: BreakpointAction

    public init(requestId: String, action: BreakpointAction) {
        self.requestId = requestId
        self.action = action
    }
}
