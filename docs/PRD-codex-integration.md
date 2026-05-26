# Product Requirements Document: Codex Rate Limits 集成

> 日期: 2026-05-26
> 状态: 草案
> 基于: `stable-cc-only` tag (commit 3013dec)

## 目标

- 在 Command Code Widget 中新增一行，显示 Codex CLI 的 rate limit 信息
- 不影响现有 Command Code 数据展示的稳定性
- 新增行不能导致 widget 卡死（前次尝试的教训）

## 用户故事

- 作为 Codex 用户，我想要在桌面上同时看到 CC 和 Codex 的用量配额，以便一眼判断是否需要切换模型
- 作为重度用户，我想知道 Codex primary (5h) 和 secondary (7d) 各自还剩多少，以及何时重置

## 功能范围

### In Scope

- 从 Codex CLI (`codex app-server`) 获取 rate limits
- 展示：plan type、primary 用量百分比、secondary 用量百分比、重置倒计时
- 与 CC 柱状图共存于同一 widget 中，新增区域不挤占柱状图空间
- 独立于 CC 数据获取：Codex 获取失败不影响 CC 展示
- 窗口大小可适当增高（从 300 → 360~380），或压缩 footer 腾空间

### Out of Scope（这个版本不做）

- Codex tokens 用量明细（目前只有 rate limit 百分比，无 token 粒度数据）
- Codex 刷新按钮独立控制（共用同一个刷新机制即可）
- Codex 账号余额

## 技术约束

- **必须稳定**：Codex RPC 使用 stdin/stdout pipe 通信，`availableData` 会永久阻塞 → 必须用 `readabilityHandler` 异步读取
- **超时保护**：Codex RPC 响应如超过 10 秒应超时放弃，不阻塞 UI
- **解耦**：Codex 获取失败不抛 error 到 CC 数据，只在 Codex 行显示 "—" 或小字 "获取失败"
- **MainActor**：所有 `@Published` 写入必须在主线程。（已有坑：`ObservableObject` 方法运行在 caller's actor，非 MainActor 写入 `@Published` 被 SwiftUI 丢弃 → UI 不更新 → 看起来像"卡死"）
- **窗口层级**：`kCGDesktopIconWindowLevel` 需要 `sendEvent` 强制 `makeKey()`，前次尝试通过删除 WidgetWindow 导致按钮/右键失效，本次保持 App.swift 的 WidgetWindow 不动

## 质量标准

- 放 4 小时不卡死（按钮/右键可操作）
- 网络断开 2 小时恢复后数据正常刷新
- Codex 进程退出/崩溃不影响 widget 存活
- CC 柱状图展示不受 Codex 获取失败影响

## UI 参考

- 添加到 footer 下方或 merge 进 footer：一行紧凑信息
- icon: `cpu` SF Symbol
- 风格: 与现有 CC footer 一致（glass material, monospaced 数字, secondary 标签文字）
- 示例布局: `[cpu] Codex Pro · 5h: 32% (2.3h) · 7d: 68% (4.7h)`
