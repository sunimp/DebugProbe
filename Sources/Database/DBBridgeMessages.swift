// DBBridgeMessages.swift
// DebugPlatform
//
// Created by Sun on 2025/12/05.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation

// MARK: - DB Command

/// 数据库命令类型
public enum DBCommandKind: String, Codable, Sendable {
    case listDatabases
    case listTables
    case describeTable
    case fetchTablePage
    case executeQuery
}

/// 数据库命令
public struct DBCommand: Codable, Sendable {
    public let requestId: String
    public let kind: DBCommandKind
    public let dbId: String?
    public let table: String?
    public let page: Int?
    public let pageSize: Int?
    public let orderBy: String?
    public let ascending: Bool?
    public let query: String?  // SQL 查询语句
    
    public init(
        requestId: String,
        kind: DBCommandKind,
        dbId: String? = nil,
        table: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        orderBy: String? = nil,
        ascending: Bool? = nil,
        query: String? = nil
    ) {
        self.requestId = requestId
        self.kind = kind
        self.dbId = dbId
        self.table = table
        self.page = page
        self.pageSize = pageSize
        self.orderBy = orderBy
        self.ascending = ascending
        self.query = query
    }
}

// MARK: - DB Response

/// 数据库响应
public struct DBResponse: Codable, Sendable {
    public let requestId: String
    public let success: Bool
    public let payload: Data?
    public let error: DBInspectorError?
    
    public init(requestId: String, success: Bool, payload: Data? = nil, error: DBInspectorError? = nil) {
        self.requestId = requestId
        self.success = success
        self.payload = payload
        self.error = error
    }
    
    /// 创建成功响应
    public static func success<T: Encodable>(requestId: String, data: T) throws -> DBResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(data)
        return DBResponse(requestId: requestId, success: true, payload: payload, error: nil)
    }
    
    /// 创建错误响应
    public static func failure(requestId: String, error: DBInspectorError) -> DBResponse {
        return DBResponse(requestId: requestId, success: false, payload: nil, error: error)
    }
}

// MARK: - Response Payload Types

/// 数据库列表响应
public struct DBListDatabasesResponse: Codable, Sendable {
    public let databases: [DBInfo]
    
    public init(databases: [DBInfo]) {
        self.databases = databases
    }
}

/// 表列表响应
public struct DBListTablesResponse: Codable, Sendable {
    public let dbId: String
    public let tables: [DBTableInfo]
    
    public init(dbId: String, tables: [DBTableInfo]) {
        self.dbId = dbId
        self.tables = tables
    }
}

/// 表结构响应
public struct DBDescribeTableResponse: Codable, Sendable {
    public let dbId: String
    public let table: String
    public let columns: [DBColumnInfo]
    
    public init(dbId: String, table: String, columns: [DBColumnInfo]) {
        self.dbId = dbId
        self.table = table
        self.columns = columns
    }
}

/// SQL 查询响应
public struct DBQueryResponse: Codable, Sendable {
    public let dbId: String
    public let query: String
    public let columns: [DBColumnInfo]
    public let rows: [DBRow]
    public let rowCount: Int
    public let executionTimeMs: Double
    
    public init(
        dbId: String,
        query: String,
        columns: [DBColumnInfo],
        rows: [DBRow],
        rowCount: Int,
        executionTimeMs: Double
    ) {
        self.dbId = dbId
        self.query = query
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.executionTimeMs = executionTimeMs
    }
}
