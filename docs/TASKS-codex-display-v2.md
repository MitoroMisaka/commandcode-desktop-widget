# 执行任务: Codex 显示优化

> 基于 PRD: `docs/PRD-codex-display-v2.md`
> 日期: 2026-05-26

## Phase 1: 数据层

- [ ] `Models.swift` CodexStatus.from() 中 `primaryPercent`/`secondaryPercent` 改为 `100 - usedPercent`（剩余）
- [ ] Commit

## Phase 2: UI 改动

- [ ] `App.swift` codexRow 数字颜色: 百分比 → `.primary`，倒计时 → `.primary.opacity(0.7)`
- [ ] `App.swift` codexRow 字体放大: 百分比 10→11（或更大），标签保持较小
- [ ] 颜色阈值: `> 80` → `< 20`（从"用了80%"变成"剩了20%"告警）
- [ ] 标签文字: "5h" → "5h剩"、"7d" → "7d剩"（更清晰）
- [ ] Commit

## Phase 3: 构建部署

- [ ] swiftc 编译无警告
- [ ] 部署到 CC.app 并重启
- [ ] Commit + push

---

> 执行指令: 按 Phase 顺序执行。
> 在 `feat/codex-integration` 分支上操作。
