// ChaosEngine.swift
// DebugPlatform
//
// Created by Sun on 2025/12/02.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - Chaos Engine

/// 故障注入引擎，用于模拟网络异常情况
public final class ChaosEngine {
    // MARK: - Singleton

    public static let shared = ChaosEngine()

    // MARK: - Properties

    private var rules: [ChaosRule] = []
    private let rulesLock = NSLock()

    /// 是否启用故障注入
    public var isEnabled: Bool = true

    // MARK: - Lifecycle

    private init() {}

    // MARK: - Rule Management

    /// 更新故障注入规则列表
    public func updateRules(_ newRules: [ChaosRule]) {
        rulesLock.lock()
        rules = newRules.sorted { $0.priority > $1.priority }
        rulesLock.unlock()
        DebugLog.debug(.chaos, "Updated \(newRules.count) rules")
    }

    /// 添加故障注入规则
    public func addRule(_ rule: ChaosRule) {
        rulesLock.lock()
        rules.append(rule)
        rules.sort { $0.priority > $1.priority }
        rulesLock.unlock()
    }

    /// 移除故障注入规则
    public func removeRule(id: String) {
        rulesLock.lock()
        rules.removeAll { $0.id == id }
        rulesLock.unlock()
    }

    /// 清空所有规则
    public func clearRules() {
        rulesLock.lock()
        rules.removeAll()
        rulesLock.unlock()
    }

    /// 获取当前规则列表
    public func getRules() -> [ChaosRule] {
        rulesLock.lock()
        defer { rulesLock.unlock() }
        return rules
    }

    // MARK: - Chaos Evaluation

    /// 评估请求是否应该注入故障
    /// - Parameter request: 请求对象
    /// - Returns: 故障结果
    public func evaluate(request: URLRequest) -> ChaosResult {
        guard isEnabled else { return .none }

        guard let rule = matchingRule(for: request) else {
            return .none
        }

        // 检查概率
        guard Double.random(in: 0...1) <= rule.probability else {
            return .none
        }

        return applyChaos(rule.chaos)
    }

    /// 评估响应是否应该注入故障
    /// - Parameters:
    ///   - request: 原始请求
    ///   - response: 响应对象
    ///   - data: 响应数据
    /// - Returns: 故障结果
    public func evaluateResponse(
        request: URLRequest,
        response _: HTTPURLResponse,
        data: Data?
    ) -> ChaosResult {
        guard isEnabled else { return .none }

        guard let rule = matchingRule(for: request) else {
            return .none
        }

        // 检查概率
        guard Double.random(in: 0...1) <= rule.probability else {
            return .none
        }

        // 只处理响应相关的故障类型
        switch rule.chaos {
        case .corruptResponse:
            if let data {
                return .corruptedData(corruptData(data))
            }
        default:
            break
        }

        return .none
    }

    // MARK: - Private Methods

    private func matchingRule(for request: URLRequest) -> ChaosRule? {
        rulesLock.lock()
        defer { rulesLock.unlock() }

        for rule in rules {
            guard rule.enabled else { continue }

            // 检查 URL 匹配
            if let pattern = rule.urlPattern, !pattern.isEmpty {
                guard let url = request.url?.absoluteString else { continue }

                // 支持通配符匹配
                if pattern.contains("*") {
                    let regex = pattern
                        .replacingOccurrences(of: ".", with: "\\.")
                        .replacingOccurrences(of: "*", with: ".*")
                    if url.range(of: regex, options: .regularExpression) == nil {
                        continue
                    }
                } else if !url.contains(pattern) {
                    continue
                }
            }

            // 检查方法匹配
            if let method = rule.method, !method.isEmpty {
                guard request.httpMethod?.uppercased() == method.uppercased() else { continue }
            }

            return rule
        }

        return nil
    }

    private func applyChaos(_ chaos: ChaosType) -> ChaosResult {
        switch chaos {
        case let .latency(min, max):
            let delay = Int.random(in: min...max)
            return .delay(milliseconds: delay)

        case .timeout:
            return .timeout

        case .connectionReset:
            return .connectionReset

        case let .randomError(codes):
            guard let code = codes.randomElement() else {
                return .none
            }
            return .errorResponse(statusCode: code)

        case .corruptResponse:
            // 响应阶段处理
            return .none

        case .slowNetwork:
            // 慢网络需要在数据传输层面处理，这里简化为延迟
            return .delay(milliseconds: Int.random(in: 1000...5000))

        case .dropRequest:
            return .drop
        }
    }

    private func corruptData(_ data: Data) -> Data {
        var mutableData = data

        // 随机损坏数据
        let corruptionCount = max(1, data.count / 100) // 损坏约 1% 的数据

        for _ in 0..<corruptionCount {
            let index = Int.random(in: 0..<mutableData.count)
            mutableData[index] = UInt8.random(in: 0...255)
        }

        return mutableData
    }
}

// MARK: - Error Types

public enum ChaosError: Error, LocalizedError {
    case timeout
    case connectionReset
    case dropped

    public var errorDescription: String? {
        switch self {
        case .timeout:
            "Request timed out (chaos injection)"
        case .connectionReset:
            "Connection reset by peer (chaos injection)"
        case .dropped:
            "Request dropped (chaos injection)"
        }
    }
}
