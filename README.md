# DebugProbe

移动 App 调试探针 SDK，用于实时捕获和分析 App 的网络请求、日志、数据库等调试信息。

> [!IMPORTANT]
>
> **本项目全部代码和文档均由 Agent AI 生成**

> **当前版本**: v1.4.0 | **最后更新**: 2025-12-11

## 功能特性

### 🌐 网络捕获
- **HTTP/HTTPS 请求捕获** - 自动拦截所有网络请求，包括 URLSession、Alamofire 等
- **WebSocket 监控** - 捕获 WebSocket 连接和消息
- **请求/响应详情** - 完整的 Headers、Body、Timing 信息
- **gRPC & Protobuf 支持** - 自动解析 Protobuf 格式数据

### 🎭 Mock Engine
- **请求 Mock** - 拦截请求并返回自定义响应
- **延迟注入** - 模拟网络延迟
- **条件匹配** - 支持 URL、Method、Header 等多种匹配规则

### 🔧 断点调试
- **请求断点** - 暂停请求并允许修改
- **响应断点** - 拦截响应并允许修改后返回
- **实时编辑** - 在 Web UI 中直接编辑请求/响应内容

### 💥 Chaos Engineering
- **延迟注入** - 模拟网络延迟
- **超时模拟** - 模拟请求超时
- **错误码注入** - 返回指定的 HTTP 错误码
- **连接重置** - 模拟网络中断
- **数据损坏** - 模拟响应数据损坏

### 📋 日志捕获
- **CocoaLumberjack 集成** - 自动捕获 DDLog 日志
- **OSLog 支持** - 捕获系统日志
- **自定义日志** - 支持自定义日志级别和分类

### 🗄️ 数据库检查
- **SQLite 浏览** - 查看 App 内的 SQLite 数据库
- **表数据查询** - 支持分页、排序、SQL 查询
- **Schema 查看** - 查看表结构

## 安装

### Swift Package Manager

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/sunimp/iOS-DebugProbe.git", from: "1.4.0")
]
```

或在 Xcode 中：
1. File → Add Package Dependencies
2. 输入仓库 URL
3. 选择版本并添加到目标

## 快速开始

### 1. 初始化

```swift
import DebugProbe

// 在 AppDelegate 或 App 入口处初始化
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {
    
    #if DEBUG
    let config = DebugProbe.Configuration(
        hubURL: URL(string: "ws://127.0.0.1:8081/debug-bridge")!,
        token: "your-device-token"
    )
    DebugProbe.shared.start(configuration: config)
    #endif
    
    return true
}
```

### 2. 配置选项

```swift
var config = DebugProbe.Configuration(
    hubURL: URL(string: "ws://localhost:8081/debug-bridge")!,
    token: "device-token"
)

// 网络捕获模式（默认自动）
config.networkCaptureMode = .automatic  // 自动拦截所有请求
// config.networkCaptureMode = .manual  // 手动注入 protocolClasses

// 网络捕获范围
config.networkCaptureScope = .all       // HTTP + WebSocket
// config.networkCaptureScope = .http   // 仅 HTTP
// config.networkCaptureScope = .webSocket // 仅 WebSocket

// 日志捕获
config.enableLogCapture = true

// 持久化（断线重连后恢复发送）
config.enablePersistence = true
config.maxPersistenceQueueSize = 100_000
config.persistenceRetentionDays = 3

DebugProbe.shared.start(configuration: config)
```

### 3. 注册数据库（可选）

```swift
import DebugProbe

// 注册要检查的数据库
DatabaseRegistry.shared.register(
    path: databasePath,
    name: "MyDatabase",
    kind: .main,
    isSensitive: false
)
```

### 4. 自定义日志（可选）

```swift
// 发送自定义调试日志
DebugProbe.shared.log(
    level: .info,
    message: "用户登录成功",
    subsystem: "Auth",
    category: "Login"
)
```

## 架构

### 插件化架构

DebugProbe 采用插件化架构，所有功能模块（网络、日志、Mock 等）均以插件形式实现：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DebugProbe SDK                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐                 │
│  │ NetworkPlugin │   │   LogPlugin   │   │WebSocketPlugin│                 │
│  │  (HTTP 捕获)   │   │  (日志捕获)    │   │  (WS 监控)    │                 │
│  └───────┬───────┘   └───────┬───────┘   └───────┬───────┘                 │
│          │                   │                   │                          │
│          ▼                   ▼                   ▼                          │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                        EventCallbacks                                  │ │
│  │  • onHTTPEvent / onLogEvent / onWebSocketEvent (捕获层 → 插件层)      │ │
│  │  • onDebugEvent (插件层 → BridgeClient)                               │ │
│  │  • mockHTTPRequest / mockWSFrame (Mock 拦截)                          │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│          │                                                                  │
│          ▼                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                       DebugBridgeClient                                │ │
│  │  • 内置事件缓冲区 (丢弃策略、持久化)                                    │ │
│  │  • WebSocket 通信                                                      │ │
│  │  • 批量发送、断线重连                                                   │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │ WebSocket
                                     ▼
                              ┌─────────────┐
                              │ Debug Hub  │
                              │  (服务端)    │
                              └─────────────┘
```

### 内置插件

| 插件 ID | 插件名称 | 功能 |
|---------|---------|------|
| `network` | NetworkPlugin | HTTP/HTTPS 请求捕获 |
| `log` | LogPlugin | 日志捕获（DDLog, OSLog） |
| `websocket` | WebSocketPlugin | WebSocket 连接监控 |
| `mock` | MockPlugin | HTTP/WS Mock 规则管理 |
| `database` | DatabasePlugin | SQLite 数据库检查 |
| `breakpoint` | BreakpointPlugin | 请求/响应断点调试 |
| `chaos` | ChaosPlugin | 故障注入（Chaos Engineering） |

### 目录结构

```
DebugProbe/
├── Sources/
│   ├── Core/
│   │   ├── DebugProbe.swift          # 主入口
│   │   ├── DebugBridgeClient.swift   # WebSocket 通信 + 事件缓冲
│   │   ├── EventPersistenceQueue.swift # 事件持久化
│   │   └── Plugin/
│   │       ├── PluginManager.swift   # 插件管理器
│   │       ├── EventCallbacks.swift  # 事件回调中心
│   │       └── PluginBridgeAdapter.swift # 命令路由适配器
│   ├── Plugins/
│   │   ├── Engines/
│   │   │   ├── BreakpointEngine.swift    # 断点引擎
│   │   │   ├── ChaosEngine.swift         # 故障注入引擎
│   │   │   └── MockRuleEngine.swift      # Mock 规则引擎
│   │   ├── NetworkPlugin.swift       # 网络插件
│   │   ├── LogPlugin.swift           # 日志插件
│   │   ├── WebSocketPlugin.swift     # WebSocket 插件
│   │   ├── MockPlugin.swift          # Mock 插件
│   │   ├── DatabasePlugin.swift      # 数据库插件
│   │   ├── BreakpointPlugin.swift    # 断点插件
│   │   └── ChaosPlugin.swift         # Chaos 插件
│   ├── Network/
│   │   ├── NetworkInstrumentation.swift  # HTTP 拦截基础设施
│   │   └── WebSocketInstrumentation.swift # WebSocket 拦截基础设施
│   ├── Log/
│   │   └── DDLogBridge.swift         # CocoaLumberjack 桥接
│   ├── Database/
│   │   └── DatabaseRegistry.swift    # 数据库注册
│   └── Models/
│       └── ...                       # 数据模型
└── Package.swift
```

## 与 DebugHub 配合使用

DebugProbe 需要配合 [DebugHub](https://github.com/sunimp/DebugPlatform) 服务端使用：

1. 启动 DebugHub 服务器
2. 在 iOS App 中配置 DebugProbe 连接到 DebugHub
3. 打开 Web UI (http://localhost:8081) 查看调试信息

## 要求

- iOS 14.0+
- macOS 12.0+
- Swift 5.9+
- Xcode 15.0+

## 可选依赖

- [CocoaLumberjack](https://github.com/CocoaLumberjack/CocoaLumberjack) - 用于日志捕获集成

## License

MIT License

## 相关项目

- [Debug Platform](https://github.com/sunimp/DebugPlatform) - 完整的调试平台（包含 Debug Hub 服务端和 Web UI）
