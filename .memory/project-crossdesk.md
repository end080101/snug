---
name: project-crossdesk
description: "CrossDesk 适配（PR #58，nexmoe）：主人定一定要合、手势必须做到和 UU 一样；上下文全在 docs/remote-adapter/crossdesk/README.md（pr58-crossdesk 分支）；11-23 调研完，等主人压缩对话后开工"
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-23T17:16:28.732Z
---

**主人 11-23 定：PR #58 一定要合。** 作者 nexmoe 在 Twitter 转发过 Snug，带来近 10 万浏览，是项目恩人；他已把分支交给我们。主人对 CrossDesk 不熟，实测随叫随到。这条推翻了 [[project-uu-vip]] 里「专注 UU、暂不接其他远控」（只对 CrossDesk 破例）。

**唯一上下文入口**：`docs/remote-adapter/crossdesk/README.md`，在 PR #58 的分支上（本地 `pr58-crossdesk`，远端 `nexmoe/snug:crossdesk-adapter`），不在 main。里面有已定决策、CrossDesk 行为事实（带 v1.7.6 行号）、两轮真机录制、核实过的 PR 问题、手势方案、16 步工作清单和实测清单。开工前先读它，结论变了改它。

**状态（11-24）**：已合并（PR #58，合并提交 0f3acb3），随 2.8.0 发布；GitHub 简介、话题已同步。#33（已关）、#35、#47、#55、讨论区 #51、PR #58 都已回复发布。上游：kunkundi 在 #200 回复「非常欢迎提交 PR」（热插拔与虚拟屏重新识别）；已另发 kunkundi/crossdesk#225 告知 Snug 已支持，并对外说了会按 #200 的思路给 CrossDesk 提 PR，**这是欠着的承诺**。

**已定**：
- 手势必须做到和 UU 一样（[[feedback-gestures-core]]），前提是手机端选「绝对鼠标」；「相对鼠标」下不翻译。屏上的「手势未生效」提示手机实测出不来，主人定砍掉（「别为了这个无关紧要的小功能堆积屎山」），改在 README 写一句
- 「提前准备虚拟屏」保留，只在装了 CrossDesk 这类远控时显示，打开前弹确认
- 门面最后统一改（[[feedback-core-before-facade]]）；直接在 PR 分支上提交（[[feedback-pr-direct-commit]]）

**对外已公开**：README 三种语言顶部「正在全力接入 CrossDesk」，立场段删了「暂不自行适配其他远控」（main b74fb1f）；#33、#35、#47、#55、讨论区 #51、PR #58 都回复了进展。README 立场段要主人重新定措辞（[[project-uu-vip]]）。

**Why:** CrossDesk 免费、开源，实测延迟接近 UU，是 UU 把虚拟屏收进 VIP 后 Snug 用户的出路。GPL 代码进 MIT 仓库会带来许可问题，所以只读不拷。
**How to apply:** 改适配层时守住 [[project-remote-adapter]] 的约定。CrossDesk 源码和原始调研报告、实验只放本机草稿区，不进仓库；有出入以文档为准。
