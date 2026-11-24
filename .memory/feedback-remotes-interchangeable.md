---
name: feedback-remotes-interchangeable
description: 界面上 UU远程、CrossDesk 等远控是并列、可换着用的适配器，不写死哪一家；名字从登记处取，各家特有的说法按能力点名
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-24T04:03:27.536Z
---

UU远程 和 CrossDesk 是两个不同的适配器，界面要让人看出它们兼容、可以切换使用，而不是绑死某一家（主人 11-23 提醒）。

**Why:** Snug 的定位是给多家远控用的增强层（远控适配层就是为此抽的），界面写死一家会让另一家的用户以为不支持，也让接第三家时到处改文案。

**How to apply:**
- 界面提到远控时用 AppState.remoteNames：这次远程的那家，不在远程时是登记的全部（「UU远程、CrossDesk」）；放不下就用不点名的「远控」
- 只对某几家成立的说法（只在启动时认屏、连上先推主屏）做成 RemoteIdentity 的能力，按声明了的那几家点名，不写死
- 例外：旧版「UU远程伴侣」是 Snug 前身，照旧点名
- 改界面文字时 design/prototype 同步（见 [[project-ui-redesign]]），文字规矩见 [[feedback-ui-style]]
