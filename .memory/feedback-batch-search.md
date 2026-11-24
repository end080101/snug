---
name: feedback-batch-search
description: 要大量查资料的活（机型库补全等）留给 workflow 一轮做，会话里不要一步步调网络搜索；主人当面问的小问题直接搜，不派 agent
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-24T16:08:03.116Z
---

需要大量网络查证的活（补全机型库、核对分辨率之类）不要在会话里一条条调网络搜索，留给主人起的 workflow 一轮并行搜完。回 issue 时碰到不认识的 App 名之类的小疑问，也先按主人给的方向写，拿不准就问，不自己去搜。

**Why:** 11-17 晚回 issue 时我想搜 #22 里的 herdr，被主人打断：「型号……会用 workflow 再去搜一轮……你就不要一步步调用网络搜索去找了」。额度紧张时，零散搜索又慢又费额度。

**例外：主人直接问的、一两次搜索就能答的问题，自己当场搜**（11-24 问 brew 收录规则时我派了 web-fetch agent，被打断：「这你派一个agent出去干啥, 你直接搜不就好了」）。不要为小查询派 agent。

**How to apply:** 发现缺资料时记下来交给下一轮 workflow（见 [[feedback-workflow-scale]]），当前回合用已有的证据和主人的判断推进；主人当面问的小问题直接用 WebSearch 查。
