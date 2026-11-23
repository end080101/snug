---
name: feedback-gestures-core
description: 原生手势是 Snug 最大的亮点，接任何远控都必须做手势翻译，不能以「远控自己处理」为由放弃
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-23T17:02:51.705Z
---

接入任何远控（CrossDesk 等），都要给它写手势适配，做到和 UU 一样的原生手势响应（单指滑滚动带惯性、长按选择、长按松手右键、关闭按钮先归位），不能退成「保留远控原生手势、只补一点」。

**Why:** 主人 11-23 反驳我「CrossDesk 保持原生手势、只补关闭按钮」的推荐：「手势是咱们这个项目最大的亮点……如果把这个给丢了，那你这个项目就等于废了」。
**How to apply:** 技术上难（如 CrossDesk 触控板模式拿不到手指位置）时，找让手势成立的路径（引导切触控模式、各家整理、拿真机数据定参数），而不是建议砍掉；做不到的部分讲清实测与论证，交主人定。见 [[project-crossdesk]]、[[feedback-product-thinking]]。
