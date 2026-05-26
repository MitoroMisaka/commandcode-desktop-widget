# 执行任务: Codex Rate Limits 集成

> 基于 TECH: `docs/TECH-codex-integration.md`
> 日期: 2026-05-26

## Phase 1: 数据模型

- [ ] `Models.swift` 新增 `CodexRateLimit`、`CodexAccount`、`CodexInitResult` Codable structs
- [ ] `Models.swift` 新增 `CodexStatus` struct（UI 展示用，含 planName/primary%/secondary%/reset 倒计时/error）
- [ ] 添加 `CodexStatus.from(rpcResult:)` 工厂方法：解析 ISO 8601 reset 时间并计算倒计时
- [ ] Commit: `feat: add Codex data models`

## Phase 2: CodexFetcher

- [ ] 创建 `Sources/CodexFetcher.swift`
- [ ] 实现 `CodexFetcher.fetch()` 非隔离方法：
  - spawn `/Applications/Codex.app/Contents/Resources/codex app-server`
  - 发送 JSON-RPC initialize 请求到 stdin
  - 使用 `stdoutHandle.readabilityHandler`（不是 `availableData`！）异步读取响应
  - 解析 JSON-RPC response，提取 account.rateLimits
  - 10s 超时 via `withThrowingTaskGroup`
  - 完成后 terminate 进程
- [ ] 返回 `CodexStatus?`（nil = 获取失败）
- [ ] Commit: `feat: add CodexFetcher with readabilityHandler-based JSON-RPC`

## Phase 3: DataFetcher 集成

- [ ] `DataFetcher.swift` 新增 `@Published var codexStatus: CodexStatus?`
- [ ] `fetchData()` 方法中新增 async let codex 并行调用 `CodexFetcher.fetch()`
- [ ] Codex 获取失败记录 log 但不设 error（解耦）
- [ ] Commit: `feat: integrate Codex fetch into DataFetcher`

## Phase 4: UI 展示

- [ ] `App.swift` 窗口高度全局调整：300 → 340（所有 `CGSize`、`frame`、`minSize`/`maxSize` 处）
- [ ] `ContentView` 新增 Codex 行，放在 footer 下方：
  - icon: `cpu` SF Symbol (13pt, secondary.opacity(0.7))
  - plan 名称（首字母大写）
  - primary: `5h: XX% (X.Xh)` 
  - secondary: `7d: XX% (X.Xh)`
  - 获取失败时显示 `—` 或小字 "获取失败"
  - 使用 HStack + 分隔符，风格与 footer 一致（monospaced 数字）
- [ ] 验证窗口高度调整后所有元素相对位置正确
- [ ] Commit: `feat: add Codex status row to widget UI`

## Phase 5: 构建验证 & 测试

- [ ] `swiftc` 编译无错误无警告
- [ ] 复制二进制到 `.build/CC.app/`，启动 widget
- [ ] 确认 CC 柱状图正常展示
- [ ] 确认 Codex 行展示 rate limits
- [ ] 右键菜单正常 → 刷新 / 退出
- [ ] 刷新按钮正常，旋转动画正常
- [ ] 拖动 + 24px 网格吸附正常
- [ ] 放 30 分钟后再次操作不卡死
- [ ] Codex 进程已退出时（手动 kill）widget 不崩溃，Codex 行显示 "获取失败"
- [ ] Commit: `chore: final build verification for Codex integration`

---

> 执行指令：按 Phase 顺序执行。每个 Phase 结束后 `git add -A && git commit`。
> 在 `feat/codex-integration` 分支上操作。
> 如果网络/进程异常导致 Codex fetch 失败，不影响 CC 展示——Codex 行静默显示 fallback。
