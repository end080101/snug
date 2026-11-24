# CrossDesk

Snug 在被控 Mac 上创建虚拟屏，CrossDesk 将画面传给控制端。手机和平板屏可以使用 App 资源库、窗口铺满和字号放大。手势由 Snug 翻译，和 UU远程 一样：单指滑滚动带惯性、长按选择、长按松手右键，需在手机端选「绝对鼠标」（选「相对鼠标」时 Snug 的屏上会提示）。

## 连接

1. 在 Snug 的「设置 → 屏幕」添加所需虚拟屏，开启「提前准备虚拟屏」。等虚拟屏出现在 macOS 的「显示器」设置里。
2. 退出并重新打开被控 Mac 上的 CrossDesk。CrossDesk 1.7.6 启动时登记显示器。新增虚拟屏后，也要重新启动 CrossDesk。
3. 用 CrossDesk 连接 Mac，在显示器菜单选 Snug 屏。手机或平板屏会显示 App 资源库。

最后一台控制端断开后，提前准备的副屏继续在线，Snug 放上去的窗口归位。关掉这个选项或退出 Snug 后可移除虚拟屏。

## 会话检测

有人远程时，CrossDesk 持有一条名为「CrossDesk is sharing the desktop」的电源断言：有入站控制端、在抓屏时建立，停止抓屏时释放。适配器每拍查一次这条断言，不读日志，也不看进程的启动时间，开机自启或看门狗拉起的 CrossDesk 同样认得出。最后一台控制端断开后，CrossDesk 可能过几秒才释放断言（实测最长 9.5 秒），会话随之结束。控制端名称和当前推流屏未知时，Snug 仍可管理虚拟屏和 App 资源库。

日志 `~/Library/Logs/CrossDesk/crossdesk.log`（及三份轮转）只用于自检。

macOS App bundle 为 `cn.crossdesk.app`，在 App 资源库中排除。

## 验证

```bash
scripts/snug check
scripts/snug remote-check crossdesk
```

在 macOS CrossDesk `v1.7.6-20261112` 上验证了启动前已上线的 Snug 测试屏。原生 CrossDesk CLI 0.2.0 连入后列出该屏，选屏后收到 600×1080 画面。Snug 诊断在连入与断开时读到对应状态。将这次的日志在隔离目录回放，Snug 正常启动后记录了连入、断开和会话结束。移动端触控和 App 资源库未在这次连接中验证。
