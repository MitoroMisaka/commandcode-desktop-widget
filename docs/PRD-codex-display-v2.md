# PRD: Codex 显示优化

> 日期: 2026-05-26
> 基于: `feat/codex-integration` branch (commit 298d6b3)

## 目标

Codex 行显示的 usage 百分比从"已用额度"改为"剩余额度"，字体加大，数字用黑色更醒目。

## 用户故事

- 作为用户，我想一眼看到 Codex 还剩多少额度，而不是用了多少
- 作为用户，我想 Codex 行的数字足够大能看清
- 作为桌面小部件，黑色数字在 glass material 背景下对比度更高

## 功能范围

### In Scope

- 额度显示: `usedPercent` → `100 - usedPercent`（剩余）
- 字体放大: codexRow 整体字号 +1~2pt
- 数字颜色: 百分比/倒计时数字 → `.primary`（黑色），标签保持 `.secondary`

### Out of Scope

- 颜色阈值逻辑不变（剩余 < 20% 时橙色告警）
- 布局结构不变
- CC 部分不变

## 技术约束

- 改动仅限 `App.swift` 和 `Models.swift` 的 CodexStatus
- 不影响 CC 数据展示
- 不影响 key window 稳定性

## 质量标准

- swiftc 编译零警告
- 右击菜单/刷新操作正常
- 窗口高度不变（340px）
