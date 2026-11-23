---
name: feedback-pr-direct-commit
description: 外部 PR 要合时直接在作者分支上追加 commit 修改，不退回让作者返工
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-23T15:13:30.761Z
---

决定要合的外部 PR，问题由我们直接在作者分支上追加 commit 修掉，保留作者原提交，不在 PR 里列问题让作者再改。

**Why:** 主人 11-23（PR #58）：「直接在他上面 commit 去改吧，不用回到他那边让他再修复，多慢啊」。
**How to apply:** `gh pr checkout` 到本地分支改；作者开了「允许维护者改动」就推回他的分支，PR 合并后功劳仍在作者名下。推到作者分支是对外动作，推之前照例问主人。审查流程见 [[feedback-workflow-scale]]。
