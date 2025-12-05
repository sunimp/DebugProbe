// DBInspector.swift
// DebugPlatform
//
// Created by Sun on 2025/12/05.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - Data Models

/// 表信息
public struct DBTableInfo: Codable, Sendable {
    public let name: String
    public let rowCount: Int?
    
    public init(name: String, rowCount: Int?) {
        self.name = name
        self.rowCount = rowCount
    }
}

/// 列信息
public struct DBColumnInfo: Codable, Sendable {
    public let name: String
    public let type: String?
    public let notNull: Bool
    public let primaryKey: Bool
    public let defaultValue: String?
    
    public init(
        name: String,
        type: String?,
        notNull: Bool,
        primaryKey: Bool,
        defaultValue: String?
    ) {
        self.name = name
        self.type = type
        self.notNull = notNull
        self.primaryKey = primaryKey
        self.defaultValue = defaultValue
    }
}

/// 行数据
public struct DBRow: Codable, Sendable {
    public let values: [String: String?]
    
    public init(values: [String: String?]) {
        self.values = values
    }
}

/// 分页查询结果
public struct DBTablePageResult: Codable, Sendable {
    public let dbId: String
    public let table: String
    public let page: Int
    public let pageSize: Int
    public let totalRows: Int?
    public let columns: [DBColumnInfo]
    public let rows: [DBRow]
    
    public init(
        dbId: String,
        table: String,
        page: Int,
        pageSize: Int,
        totalRows: Int?,
        columns: [DBColumnInfo],
        rows: [DBRow]
    ) {
        self.dbId = dbId
        self.table = table
        self.page = page
        self.pageSize = pageSize
        self.totalRows = totalRows
        self.columns = columns
        self.rows = rows
    }
}

/// 数据库信息（包含表数量）
public struct DBInfo: Codable, Sendable {
    public let descriptor: DatabaseDescriptor
    public let tableCount: Int
    public let fileSizeBytes: Int64?
    
    public init(descriptor: DatabaseDescriptor, tableCount: Int, fileSizeBytes: Int64?) {
        self.descriptor = descriptor
        self.tableCount = tableCount
        self.fileSizeBytes = fileSizeBytes
    }
}

// MARK: - Errors

/// DB Inspector 错误
public enum DBInspectorError: Error, Codable, Sendable {
    case databaseNotFound(String)
    case tableNotFound(String)
    case invalidQuery(String)
    case timeout
    case accessDenied(String)
    case internalError(String)
    
    public var message: String {
        switch self {
        case .databaseNotFound(let id):
            return "Database not found: \(id)"
        case .tableNotFound(let name):
            return "Table not found: \(name)"
        case .invalidQuery(let reason):
            return "Invalid query: \(reason)"
        case .timeout:
            return "Operation timeout"
        case .accessDenied(let reason):
            return "Access denied: \(reason)"
        case .internalError(let msg):
            return "Internal error: \(msg)"
        }
    }
}

// MARK: - Protocol

/// DB Inspector 协议
public protocol DBInspector: Sendable {
    /// 列出所有数据库
    func listDatabases() async throws -> [DBInfo]
    
    /// 列出指定数据库的所有表
    func listTables(dbId: String) async throws -> [DBTableInfo]
    
    /// 获取表结构
    func describeTable(dbId: String, table: String) async throws -> [DBColumnInfo]
    
    /// 分页获取表数据
    func fetchTablePage(
        dbId: String,
        table: String,
        page: Int,
        pageSize: Int,
        orderBy: String?,
        ascending: Bool
    ) async throws -> DBTablePageResult
}
