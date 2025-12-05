// SQLiteInspector.swift
// DebugPlatform
//
// Created by Sun on 2025/12/05.
// Copyright © 2025 Sun. All rights reserved.
//

import Foundation
import SQLite3

/// SQLite 数据库检查器实现
/// 使用原生 SQLite3 API，只读访问，不依赖 GRDB
public final class SQLiteInspector: DBInspector, @unchecked Sendable {
    
    /// 单例
    public static let shared = SQLiteInspector()
    
    /// 数据库注册表
    private let registry: DatabaseRegistry
    
    /// SQLite busy_timeout（毫秒）- 等待数据库锁的最大时间
    private let busyTimeout: Int32 = 5000  // 5 秒
    
    /// 查询执行超时（秒）- 超时后强制中断查询
    private let queryExecutionTimeout: TimeInterval = 10.0
    
    /// 单页最大行数
    private let maxPageSize = 500
    
    /// SQL 查询最大返回行数
    private let maxQueryRows = 1000
    
    /// 串行队列确保线程安全
    private let queue = DispatchQueue(label: "com.debug.dbinspector", qos: .userInitiated)
    
    private init(registry: DatabaseRegistry = .shared) {
        self.registry = registry
    }
    
    // MARK: - DBInspector Protocol
    
    public func listDatabases() async throws -> [DBInfo] {
        let descriptors = registry.allDescriptors()
        
        var results: [DBInfo] = []
        for descriptor in descriptors {
            guard let url = registry.url(for: descriptor.id) else { continue }
            
            do {
                let (tableCount, fileSize) = try await withCheckedThrowingContinuation { continuation in
                    queue.async {
                        do {
                            let tableCount = try self.getTableCount(at: url)
                            let fileSize = self.getFileSize(at: url)
                            continuation.resume(returning: (tableCount, fileSize))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                results.append(DBInfo(
                    descriptor: descriptor,
                    tableCount: tableCount,
                    fileSizeBytes: fileSize
                ))
            } catch {
                // 如果无法打开数据库，仍然显示它但标记为不可用
                results.append(DBInfo(
                    descriptor: descriptor,
                    tableCount: 0,
                    fileSizeBytes: nil
                ))
            }
        }
        
        return results
    }
    
    public func listTables(dbId: String) async throws -> [DBTableInfo] {
        guard let url = registry.url(for: dbId) else {
            throw DBInspectorError.databaseNotFound(dbId)
        }
        
        // 检查敏感数据库
        if let descriptor = registry.descriptor(for: dbId), descriptor.isSensitive {
            throw DBInspectorError.accessDenied("Cannot inspect sensitive database")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let tables = try self.queryTables(at: url)
                    continuation.resume(returning: tables)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func describeTable(dbId: String, table: String) async throws -> [DBColumnInfo] {
        guard let url = registry.url(for: dbId) else {
            throw DBInspectorError.databaseNotFound(dbId)
        }
        
        // 检查敏感数据库
        if let descriptor = registry.descriptor(for: dbId), descriptor.isSensitive {
            throw DBInspectorError.accessDenied("Cannot inspect sensitive database")
        }
        
        // 验证表名安全性
        guard isValidIdentifier(table) else {
            throw DBInspectorError.invalidQuery("Invalid table name")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let columns = try self.queryColumns(at: url, table: table)
                    continuation.resume(returning: columns)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func fetchTablePage(
        dbId: String,
        table: String,
        page: Int,
        pageSize: Int,
        orderBy: String?,
        ascending: Bool
    ) async throws -> DBTablePageResult {
        guard let url = registry.url(for: dbId) else {
            throw DBInspectorError.databaseNotFound(dbId)
        }
        
        // 检查敏感数据库
        if let descriptor = registry.descriptor(for: dbId), descriptor.isSensitive {
            throw DBInspectorError.accessDenied("Cannot inspect sensitive database")
        }
        
        // 验证表名安全性
        guard isValidIdentifier(table) else {
            throw DBInspectorError.invalidQuery("Invalid table name")
        }
        
        // 验证 orderBy 列名安全性
        if let orderBy = orderBy, !isValidIdentifier(orderBy) {
            throw DBInspectorError.invalidQuery("Invalid column name for orderBy")
        }
        
        // 限制 pageSize
        let safePageSize = min(max(1, pageSize), maxPageSize)
        let safePage = max(1, page)
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.queryTablePage(
                        at: url,
                        dbId: dbId,
                        table: table,
                        page: safePage,
                        pageSize: safePageSize,
                        orderBy: orderBy,
                        ascending: ascending
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 执行自定义 SQL 查询（只允许 SELECT）
    public func executeQuery(dbId: String, query: String) async throws -> DBQueryResponse {
        guard let url = registry.url(for: dbId) else {
            throw DBInspectorError.databaseNotFound(dbId)
        }
        
        // 检查敏感数据库
        if let descriptor = registry.descriptor(for: dbId), descriptor.isSensitive {
            throw DBInspectorError.accessDenied("Cannot query sensitive database")
        }
        
        // 安全检查：只允许 SELECT 语句
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.uppercased().hasPrefix("SELECT") else {
            throw DBInspectorError.invalidQuery("Only SELECT statements are allowed")
        }
        
        // 检查是否包含危险操作
        let dangerousPatterns = ["DROP", "DELETE", "INSERT", "UPDATE", "ALTER", "CREATE", "ATTACH", "DETACH"]
        let upperQuery = trimmedQuery.uppercased()
        for pattern in dangerousPatterns {
            if upperQuery.contains(pattern) {
                throw DBInspectorError.invalidQuery("Query contains forbidden operation: \(pattern)")
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.executeQueryInternal(at: url, dbId: dbId, query: trimmedQuery)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private SQLite Operations
    
    private func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        
        // 以只读模式打开
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        
        guard result == SQLITE_OK, let database = db else {
            if let db = db {
                sqlite3_close(db)
            }
            throw DBInspectorError.internalError("Failed to open database: \(result)")
        }
        
        // 设置 busy_timeout - 等待数据库锁的最大时间
        sqlite3_busy_timeout(database, busyTimeout)
        
        return database
    }
    
    private func getTableCount(at url: URL) throws -> Int {
        let db = try openDatabase(at: url)
        defer { sqlite3_close(db) }
        
        let sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to prepare statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw DBInspectorError.internalError("Failed to execute query")
        }
        
        return Int(sqlite3_column_int(stmt, 0))
    }
    
    private func getFileSize(at url: URL) -> Int64? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
    }
    
    private func queryTables(at url: URL) throws -> [DBTableInfo] {
        let db = try openDatabase(at: url)
        defer { sqlite3_close(db) }
        
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to prepare statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        var tables: [DBTableInfo] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: namePtr)
            
            // 获取行数
            let rowCount = try? getRowCount(db: db, table: name)
            
            tables.append(DBTableInfo(name: name, rowCount: rowCount))
        }
        
        return tables
    }
    
    private func getRowCount(db: OpaquePointer, table: String) throws -> Int {
        // 使用引号包裹表名
        let sql = "SELECT COUNT(*) FROM \"\(table)\""
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to count rows")
        }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw DBInspectorError.internalError("Failed to count rows")
        }
        
        return Int(sqlite3_column_int(stmt, 0))
    }
    
    private func queryColumns(at url: URL, table: String) throws -> [DBColumnInfo] {
        let db = try openDatabase(at: url)
        defer { sqlite3_close(db) }
        
        // 验证表是否存在
        guard try tableExists(db: db, table: table) else {
            throw DBInspectorError.tableNotFound(table)
        }
        
        let sql = "PRAGMA table_info(\"\(table)\")"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to prepare statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        var columns: [DBColumnInfo] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let type = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let notNull = sqlite3_column_int(stmt, 3) != 0
            let defaultValue = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let primaryKey = sqlite3_column_int(stmt, 5) != 0
            
            columns.append(DBColumnInfo(
                name: name,
                type: type,
                notNull: notNull,
                primaryKey: primaryKey,
                defaultValue: defaultValue
            ))
        }
        
        return columns
    }
    
    private func queryTablePage(
        at url: URL,
        dbId: String,
        table: String,
        page: Int,
        pageSize: Int,
        orderBy: String?,
        ascending: Bool
    ) throws -> DBTablePageResult {
        let db = try openDatabase(at: url)
        defer { sqlite3_close(db) }
        
        // 验证表是否存在
        guard try tableExists(db: db, table: table) else {
            throw DBInspectorError.tableNotFound(table)
        }
        
        // 获取列信息
        let columns = try queryColumnsInternal(db: db, table: table)
        
        // 获取总行数
        let totalRows = try? getRowCount(db: db, table: table)
        
        // 构建查询 SQL
        var sql = "SELECT * FROM \"\(table)\""
        
        if let orderBy = orderBy {
            sql += " ORDER BY \"\(orderBy)\" \(ascending ? "ASC" : "DESC")"
        }
        
        let offset = (page - 1) * pageSize
        sql += " LIMIT \(pageSize) OFFSET \(offset)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to prepare statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        var rows: [DBRow] = []
        let columnCount = sqlite3_column_count(stmt)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [String: String?] = [:]
            
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(stmt, i))
                let value = getColumnValue(stmt: stmt, index: i)
                values[columnName] = value
            }
            
            rows.append(DBRow(values: values))
        }
        
        return DBTablePageResult(
            dbId: dbId,
            table: table,
            page: page,
            pageSize: pageSize,
            totalRows: totalRows,
            columns: columns,
            rows: rows
        )
    }
    
    private func executeQueryInternal(at url: URL, dbId: String, query: String) throws -> DBQueryResponse {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let db = try openDatabase(at: url)
        defer { sqlite3_close(db) }
        
        // 设置超时定时器 - 超时后强制中断查询
        var timedOut = false
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            timedOut = true
            sqlite3_interrupt(db)
            DebugLog.warning("[DBInspector] Query timeout after \(self.queryExecutionTimeout)s, interrupted")
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + queryExecutionTimeout,
            execute: timeoutWorkItem
        )
        defer { timeoutWorkItem.cancel() }
        
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &stmt, nil)
        
        if timedOut {
            sqlite3_finalize(stmt)
            throw DBInspectorError.timeout
        }
        
        guard prepareResult == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DBInspectorError.invalidQuery(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }
        
        // 获取列信息
        let columnCount = sqlite3_column_count(stmt)
        var columns: [DBColumnInfo] = []
        
        for i in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(stmt, i))
            let type = sqlite3_column_decltype(stmt, i).map { String(cString: $0) }
            columns.append(DBColumnInfo(
                name: name,
                type: type,
                notNull: false,
                primaryKey: false,
                defaultValue: nil
            ))
        }
        
        // 执行查询并获取结果（限制最多 maxQueryRows 行）
        var rows: [DBRow] = []
        
        while !timedOut && rows.count < maxQueryRows {
            let stepResult = sqlite3_step(stmt)
            
            if timedOut {
                break
            }
            
            if stepResult == SQLITE_DONE {
                break
            } else if stepResult == SQLITE_ROW {
                var values: [String: String?] = [:]
                
                for i in 0..<columnCount {
                    let columnName = String(cString: sqlite3_column_name(stmt, i))
                    let value = getColumnValue(stmt: stmt, index: i)
                    values[columnName] = value
                }
                
                rows.append(DBRow(values: values))
            } else if stepResult == SQLITE_INTERRUPT {
                // 查询被中断（超时）
                break
            } else {
                // 其他错误
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw DBInspectorError.internalError("Query failed: \(errorMessage)")
            }
        }
        
        // 检查是否因超时而中断
        if timedOut {
            throw DBInspectorError.timeout
        }
        
        let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000  // 转为毫秒
        
        return DBQueryResponse(
            dbId: dbId,
            query: query,
            columns: columns,
            rows: rows,
            rowCount: rows.count,
            executionTimeMs: executionTime
        )
    }
    
    private func queryColumnsInternal(db: OpaquePointer, table: String) throws -> [DBColumnInfo] {
        let sql = "PRAGMA table_info(\"\(table)\")"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to prepare statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        var columns: [DBColumnInfo] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let type = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let notNull = sqlite3_column_int(stmt, 3) != 0
            let defaultValue = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let primaryKey = sqlite3_column_int(stmt, 5) != 0
            
            columns.append(DBColumnInfo(
                name: name,
                type: type,
                notNull: notNull,
                primaryKey: primaryKey,
                defaultValue: defaultValue
            ))
        }
        
        return columns
    }
    
    private func tableExists(db: OpaquePointer, table: String) throws -> Bool {
        let sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBInspectorError.internalError("Failed to check table existence")
        }
        defer { sqlite3_finalize(stmt) }
        
        // 使用 SQLITE_TRANSIENT 确保 SQLite 复制字符串
        // -1 表示使用 strlen 计算长度，SQLITE_TRANSIENT 告诉 SQLite 复制数据
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, table, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw DBInspectorError.internalError("Failed to check table existence")
        }
        
        return sqlite3_column_int(stmt, 0) > 0
    }
    
    private func getColumnValue(stmt: OpaquePointer?, index: Int32) -> String? {
        guard let stmt = stmt else { return nil }
        
        let type = sqlite3_column_type(stmt, index)
        
        switch type {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            if let text = sqlite3_column_text(stmt, index) {
                return String(cString: text)
            }
            return nil
        case SQLITE_BLOB:
            let bytes = sqlite3_column_bytes(stmt, index)
            if let blob = sqlite3_column_blob(stmt, index) {
                let data = Data(bytes: blob, count: Int(bytes))
                return data.base64EncodedString()
            }
            return nil
        default:
            return nil
        }
    }
    
    // MARK: - Validation
    
    /// 验证标识符（表名、列名）是否安全
    private func isValidIdentifier(_ identifier: String) -> Bool {
        // 只允许字母、数字、下划线
        // 不能以数字开头
        // 长度限制
        guard !identifier.isEmpty, identifier.count <= 128 else { return false }
        
        let pattern = "^[a-zA-Z_][a-zA-Z0-9_]*$"
        return identifier.range(of: pattern, options: .regularExpression) != nil
    }
}
