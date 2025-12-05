// ChaosRule.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - 故障注入规则

/// 故障注入规则，用于模拟网络异常情况
public struct ChaosRule: Codable, Identifiable {
    public let id: String
    public var name: String
    public var urlPattern: String?
    public var method: String?
    public var probability: Double // 触发概率 0.0-1.0
    public var chaos: ChaosType
    public var enabled: Bool
    public var priority: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        urlPattern: String? = nil,
        method: String? = nil,
        probability: Double = 1.0,
        chaos: ChaosType,
        enabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.method = method
        self.probability = min(max(probability, 0), 1)
        self.chaos = chaos
        self.enabled = enabled
        self.priority = priority
    }
}

// MARK: - 故障类型

public enum ChaosType: Codable {
    /// 随机延迟 (最小毫秒, 最大毫秒)
    case latency(min: Int, max: Int)

    /// 请求超时
    case timeout

    /// 连接重置
    case connectionReset

    /// 随机返回错误码
    case randomError(codes: [Int])

    /// 损坏响应数据
    case corruptResponse

    /// 模拟慢网络 (字节/秒)
    case slowNetwork(bytesPerSecond: Int)

    /// 随机丢弃请求（不响应）
    case dropRequest

    private enum CodingKeys: String, CodingKey {
        case type
        case minLatency
        case maxLatency
        case errorCodes
        case bytesPerSecond
    }

    private enum TypeValue: String, Codable {
        case latency
        case timeout
        case connectionReset
        case randomError
        case corruptResponse
        case slowNetwork
        case dropRequest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeValue.self, forKey: .type)

        switch type {
        case .latency:
            let min = try container.decode(Int.self, forKey: .minLatency)
            let max = try container.decode(Int.self, forKey: .maxLatency)
            self = .latency(min: min, max: max)
        case .timeout:
            self = .timeout
        case .connectionReset:
            self = .connectionReset
        case .randomError:
            let codes = try container.decode([Int].self, forKey: .errorCodes)
            self = .randomError(codes: codes)
        case .corruptResponse:
            self = .corruptResponse
        case .slowNetwork:
            let bps = try container.decode(Int.self, forKey: .bytesPerSecond)
            self = .slowNetwork(bytesPerSecond: bps)
        case .dropRequest:
            self = .dropRequest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .latency(min, max):
            try container.encode(TypeValue.latency, forKey: .type)
            try container.encode(min, forKey: .minLatency)
            try container.encode(max, forKey: .maxLatency)
        case .timeout:
            try container.encode(TypeValue.timeout, forKey: .type)
        case .connectionReset:
            try container.encode(TypeValue.connectionReset, forKey: .type)
        case let .randomError(codes):
            try container.encode(TypeValue.randomError, forKey: .type)
            try container.encode(codes, forKey: .errorCodes)
        case .corruptResponse:
            try container.encode(TypeValue.corruptResponse, forKey: .type)
        case let .slowNetwork(bps):
            try container.encode(TypeValue.slowNetwork, forKey: .type)
            try container.encode(bps, forKey: .bytesPerSecond)
        case .dropRequest:
            try container.encode(TypeValue.dropRequest, forKey: .type)
        }
    }
}

// MARK: - 故障注入结果

public enum ChaosResult {
    /// 无故障，正常继续
    case none

    /// 添加延迟（毫秒）
    case delay(milliseconds: Int)

    /// 超时错误
    case timeout

    /// 连接重置错误
    case connectionReset

    /// 返回错误响应
    case errorResponse(statusCode: Int)

    /// 损坏的响应数据
    case corruptedData(Data)

    /// 丢弃请求（不响应）
    case drop
}
