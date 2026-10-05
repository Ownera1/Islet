# Agent 页与收起态歌词

Agent 页提供“全部 Agent”和五个真实集成框架的下拉选择；选择写入 `selectedAgentFramework`，重启后恢复。新用户和无效旧值默认总览。下拉面板将全部选项固定在顶部，按运行中、已连接、未连接分组，其余选项可滚动。名称完整显示，只有任务描述省略；菜单滚动到底时取消底部淡出。

总览只显示存在实时会话的 Agent，运行项优先，组内保持原框架顺序。同一框架多个会话时优先展示等待审批/回答的会话，再选活动会话和最近活动。安装了 Hook 并不等于已连接。左栏宽 212 点，右侧保留会话详情、真实任务列表、审批和回答；面板沿用当前 640 × 320 外部尺寸。

“设置 → Agent 与订阅 → Agent 显示”可以切换单行和双行（默认）；`agentOverviewStyle` 使用 Defaults 持久化，立即生效且保留当前 Agent 选择。单行显示圆点、全名、任务描述和状态指示；双行显示框架色竖条、全名和副标题。减少动态效果时指示器静止，切换使用淡入淡出。

参考文档和 HTML 用于样式与布局；HTML 中的卡片样式、演示控件及额外四种框架未作为真实功能加入。

后台服务状态独立显示：只有收到“Agent 服务已就绪”才显示绿色圆点，未启动或错误状态显示灰色。审批、问题到达时自动选择其所属框架并展开 Agent 页，避免此前筛选其他工具时看不到请求。

在“设置 → Media”中选择“收起时显示歌词”：

| 设置 | 无硬件刘海的屏幕 | 有硬件刘海的屏幕 |
| --- | --- | --- |
| 关闭 | 不显示 | 不显示 |
| 仅外接显示器（默认） | 胶囊中间 | 不显示 |
| 所有显示器 | 胶囊中间 | 刘海下方 300 × 24 点歌词条 |

屏幕类型按照每个窗口的 `screenUUID` 对应的 `NSScreen.safeAreaInsets.top` 判断。窗口换屏和屏幕参数变化会刷新；已有多屏窗口逻辑继续使用独立的 ViewModel。

有同步歌词或纯音乐时，胶囊宽度固定约 440 点，不随句子长短变化。无歌词、加载中或歌词关闭时，无硬件刘海屏的胶囊宽约 230 点；有硬件刘海屏保留原来的硬件避让宽度。主胶囊高度仍由现有显示器设置决定。内置屏歌词条独立伸出，不挤占主胶囊高度。

收起态复用 `LyricsDocument`、`Lyrics.index`、`Lyrics.progress` 和 `MusicManager.estimatedPlaybackPosition`。显示当前一句，已唱字为白色，未唱字为半亮；长句按当前句完整时间区间滚动，首尾各停留 10%。暂停保留歌词并压暗，频谱停住。间奏和纯音乐显示三个圆点；不显示加载或未找到歌词的提示。减少动态效果关闭滚动和揭示，保留淡入淡出与当前句更新。

两项数据边界：只有纯文本、没有同步时间戳的歌词无法确定“当前一句”，因此收起态保持窄形态；普通 LRC 没有明确演唱结束时间，只有空白时间标签能可靠识别间奏。YRC/逐字时间戳可在明确的句末切到间奏圆点。展开页仍保留原有纯文本歌词显示和歌词数据源。

当前仓库没有任务完成占用收起区域的提醒。现有审批/问题提醒会展开面板，本次继续沿用；歌词也会避让电池、系统 HUD 和音乐信息预览。这些状态结束后恢复歌词。

## 验证

```sh
./scripts/build-app.sh
swift test --package-path Packages/NotchIntegrations --scratch-path build/IntegrationPackage
./scripts/test-agent-lyrics.sh
./scripts/test-hud-lifecycle.sh
./scripts/test-notch-surface.sh
./scripts/test-pan-gesture.sh
```

`test-agent-lyrics.sh` 使用生产 AgentMonitor、AgentPanelView 和歌词渲染组件，隔离后台 XPC/媒体服务，检查框架选择持久化、会话筛选、审批自动选框架。21 张组件预览输出到 `build/agent-lyrics-previews/`。Agent 面板和下拉覆盖层用 NSHostingView 渲染，总览行、歌词和设置预览用 ImageRenderer。歌词预览里的封面和频谱使用固定示例数据，不是实际音乐播放截图。

实际双屏播放、热插拔、合盖、换句动画和屏幕阅读器仍需实机验收；静态组件渲染不能替代这些验证。

## 显示器与 HUD 修复

自动切换开关变更会重新选择显示器、定位窗口并恢复可见性。首选显示器存在时使用首选；首选断开且开启自动切换时选择主屏（无主屏对象时选择首个可用屏幕），关闭自动切换则隐藏；重连恢复首选，持久化偏好不被回退覆盖。屏幕布局比较保存 UUID 与 frame 值，避免可变 NSScreen 对象掩盖位置变化。

此前权限在非沙盒 Helper 查询，但媒体键在沙盒主应用创建 HID event tap，失败时无提示。现在 Helper 创建 session event tap，仅接收音量、静音、屏幕亮度和键盘背光七个媒体键；播放键和普通键不拦截。权限检查探测同一 Helper 的实际拦截能力；按下与释放均消费，仅将按下和重复事件送到主应用执行原来的系统动作。主应用沙盒保持开启。连接失效移除 tap；超时禁用后重新启用。开关快速切换时用请求代次避免延迟回复重新开启 HUD，失败和断线显示明确提示。

145 项核心测试覆盖媒体键解码、显示器断连/开关/重连与 Agent 聚合；HUD 回归脚本验证失败、重试、修饰键、断线和延迟回复。系统 Accessibility 的实际 TCC 授权、物理媒体键与双屏热插拔未由隔离测试代替；新版本若系统保留旧授权条目，需要按 HUD 设置提示重新启用 Islet。

Helper 的 `XPCService.RunLoopType` 显式设置为 `NSRunLoop`，确保主线程上的 CFRunLoop event tap source 被分发。XPC 默认使用 `dispatch_main`，不应依赖它分发 CFRunLoop source；属性定义见 [Apple XPC Services 文档](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)。发布校验从真实已编译 Helper 的 Info.plist 检查此值，同时检查主应用和 Helper 均没有调试权限。
