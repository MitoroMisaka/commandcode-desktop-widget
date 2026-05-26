# 技术方案: Codex Rate Limits 集成

> 基于 PRD: `docs/PRD-codex-integration.md`
> 日期: 2026-05-26

## 架构概览

```
Widget App
├── App.swift               (不变: WidgetWindow + sendEvent makeKey)
├── DataFetcher.swift        (新增: Codex fetch 方法，保持非阻塞)
├── Models.swift             (新增: CodexRateLimit struct)
├── TokenExtractor.swift     (不变)
└── CodexFetcher.swift       (新增: JSON-RPC over stdin/stdout pipe)
```

**数据流**:
```
codex app-server (stdin)  ──JSON-RPC──>  CodexFetcher (readabilityHandler)
                                              │
                                              ▼
                                         DataFetcher.fetch()  (并行)
                                              │
                                    ┌─────────┴─────────┐
                                    ▼                   ▼
                              CC 数据 (已有)      Codex 数据 (新增)
                                    │                   │
                                    └───────┬───────────┘
                                            ▼
                                    @Published 更新 UI
```

**关键原则**: CC 和 Codex 数据获取完全独立。CC 失败不影响 Codex 行；Codex 失败不影响 CC 柱状图。

## 技术选型

| 层 | 选择 | 理由 |
|----|------|------|
| 通信协议 | JSON-RPC 2.0 over stdin/stdout | Codex CLI 的标准接口 |
| 进程通信 | Foundation `Process` + `Pipe` | 纯 Swift，无需外部依赖 |
| 异步读取 | `FileHandle.readabilityHandler` | 避免 `availableData` 永久阻塞 |
| 数据模型 | `Codable` structs | 保持与 Models.swift 一致 |
| 超时 | `withThrowingTaskGroup` (10s) | 已有模式，独立于 CC 的 25s |

## Codex RPC 协议

进程: `/Applications/Codex.app/Contents/Resources/codex app-server`

**双请求序列**（不能关闭 stdin，两轮通信）：

### Step 1: initialize

```
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.2.0","clientInfo":{"name":"CommandCodeWidget","version":"1.0.0"}}}
← {"id":1,"result":{"userAgent":"CommandCodeWidget/...","codexHome":"~/.codex","platformFamily":"unix","platformOs":"macos"}}
```

**注意**: `clientInfo` 是必填字段，缺少会返回 `-32600` 错误。

### Step 2: account/rateLimits/read

```
→ {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}
← {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":33,"resetsAt":1779813312},"secondary":{"usedPercent":86,"resetsAt":1780201585},"planType":"plus"}}}
```

`resetsAt` 是 **Unix 时间戳**（Int 秒），不是 ISO 8601 字符串。

### 读取方式（readabilityHandler）

```
Process.launch()
stdoutHandle.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else {
        // EOF → stdin closed → process exits
        handle.readabilityHandler = nil
        return
    }
    buffer.append(data)
    // Parse lines from buffer (JSON-RPC: one line = one message)
    while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer[..<newline]
        buffer.removeSubrange(...newline)
        handleResponse(line)
    }
}
```

不可以用 `handle.availableData` 在同步/async 上下文中阻塞等待——已经验证过会永久 hang。（详见 memory 中的教训）

## 数据模型

```swift
struct CodexRateLimitBucket: Codable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: Int  // Unix timestamp (seconds)
}

struct CodexRateLimits: Codable {
    let primary: CodexRateLimitBucket
    let secondary: CodexRateLimitBucket
    let planType: String
}

struct CodexRPCResult: Codable {
    let rateLimits: CodexRateLimits
}
```

UI 展示用:
```swift
struct CodexStatus {
    let planName: String?        // "Plus" / "Pro" / nil=失败
    let primaryPercent: Double?  // 33.0 → "33%"
    let primaryReset: String?    // "2.3h" or "45m" 倒计时
    let secondaryPercent: Double?
    let secondaryReset: String?
    let error: String?
}

## 窗口尺寸

**决定**: 高度从 300 → 340（增加 40px），Codex 行放在 footer 下方。

理由:
- 不压缩柱状图区域（已是 130px + 标签 + 图例）
- footer 已经紧凑（Cost / Tokens / Runs 三列）
- 40px 刚好容纳一行 14px 文字 + padding
- 不改成自适应高度（minSize=maxSize 锁定是设计选择，避免闪烁）

备选方案（已否决）:
- B: 合并进 footer  → footer 太挤，5 列信息混乱
- C: 替换 footer → 丢失 CC 汇总信息，用户明确要求两者都有

## ADR

### ADR-001: 独立的 CodexFetcher vs 合并进 DataFetcher

**背景**: Codex 数据获取逻辑是否需要单独文件

**选项**:
- A: 合并进 DataFetcher.swift — 少一个文件，fetch() 方法内并行
- B: 独立 CodexFetcher.swift — 关注点分离

**决定**: 选 B，因为 (1) DataFetcher.swift 已 105 行，再加管道管理会超 200 行；(2) Codex 的 pipe/protocol 逻辑与 HTTP 完全不同，混在一起可读性差；(3) 独立文件方便后续出问题时单独替换而不影响 CC

### ADR-002: Process 生命周期管理

**背景**: `codex app-server` 启动慢（~2s），每次都 spawn 还是 keep-alive

**选项**:
- A: 每次 refresh 启动新进程，读取后杀死
- B: 启动后保持进程，refresh 时复用

**决定**: 选 A（每次重新 spawn），因为 (1) 刷新间隔 30min，不值得 keep-alive；但实际上 app-server 需要两轮 RPC（initialize → account/rateLimits/read），不能关闭 stdin 直到两轮都完成。进程在 timeout 或成功/失败后 terminate。

### ADR-003: 窗口高度调整策略

**背景**: PRD 提到两种方案——增高窗口或压缩 footer

**决定**: 窗口增高到 340（+40px），因为 footer 已经在最小化边缘（三列 14px 数字 + 9px 标签），增加第四列会让可读性急剧下降。40px 的增量在 432px 宽的窗口上比例合理。

## 文件变更清单（预估）

| 文件 | 操作 | 说明 |
|------|------|------|
| Sources/CodexFetcher.swift | 新增 | JSON-RPC 通信，readabilityHandler 读取，10s 超时 |
| Sources/Models.swift | 修改 | 新增 CodexStatus struct |
| Sources/App.swift | 修改 | (1) 窗口高度 300→340 (2) ContentView 新增 Codex 行 (3) DataFetcher 新增 @Published codexStatus |
| Sources/DataFetcher.swift | 修改 | fetchData() 新增并行 Codex fetch |
| docs/PRD-codex-integration.md | 新增 | 本 PRD |
| docs/TECH-codex-integration.md | 新增 | 本 TECH |
| docs/TASKS-codex-integration.md | 新增 | 执行任务 |
