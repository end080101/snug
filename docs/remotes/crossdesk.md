# CrossDesk

Snug 在被控 Mac 上创建虚拟屏，CrossDesk 将画面传给控制端。手机和平板屏可以使用 App 资源库、窗口铺满和字号放大。CrossDesk 处理自己的点按、拖动、滚动和右键。

## 连接

1. 在 Snug 的「设置 → 屏幕」添加所需虚拟屏，开启「提前准备虚拟屏」。等虚拟屏出现在 macOS 的「显示器」设置里。
2. 退出并重新打开被控 Mac 上的 CrossDesk。CrossDesk 1.7.6 启动时登记显示器。新增虚拟屏后，也要重新启动 CrossDesk。
3. 用 CrossDesk 连接 Mac，在显示器菜单选 Snug 屏。手机或平板屏会显示 App 资源库。

最后一台控制端断开后，提前准备的副屏继续在线，Snug 放上去的窗口归位。关掉这个选项或退出 Snug 后可移除虚拟屏。

## 会话检测

适配器只读 `~/Library/Logs/CrossDesk/crossdesk.log` 及其三个轮转文件，并按当前 CrossDesk 进程启动时间排除旧记录。抓屏启动表示连入，最后一台控制端断开表示会话结束。抓屏启动失败、停止或日志重新初始化时清掉旧状态。控制端名称和当前推流屏未知时，Snug 仍可管理虚拟屏和 App 资源库。

macOS App bundle 为 `cn.crossdesk.app`，在 App 资源库中排除。

## 验证

```bash
scripts/snug check
scripts/snug remote-check crossdesk
```

在 macOS CrossDesk `v1.7.6-20261112` 上验证了启动前已上线的 Snug 测试屏。原生 CrossDesk CLI 0.2.0 连入后列出该屏，选屏后收到 600×1080 画面。Snug 诊断在连入与断开时读到对应状态。将这次的日志在隔离目录回放，Snug 正常启动后记录了连入、断开和会话结束。移动端触控和 App 资源库未在这次连接中验证。
