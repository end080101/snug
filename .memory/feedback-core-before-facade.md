---
name: feedback-core-before-facade
description: 先把内核打通、实测过，再统一改 README 等对外门面；一个时刻只专注一件事
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-23T15:13:26.939Z
---

接入新能力时，先把内核（连接判定、建屏、手势、会话）打通并实测过，README、文档措辞、对外立场这些门面放到最后，一次性全面改。

**Why:** 主人 11-23（PR #58 CrossDesk）：「等我们真正接入完了再全面去改」「在一个时刻，最好就专注于一个东西」。内核没定，门面写了也要返工。
**How to apply:** 审、改外部 PR 时，PR 里的 README 和门面改动先不动、不讨论，留到内核收尾后单独一轮处理。立场措辞仍按 [[project-uu-vip]] 由主人定。
