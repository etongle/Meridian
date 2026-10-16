# 世界时钟 · 设计与功能检查

final result: passed

## 比较目标与状态

- 视觉来源：用户选定的第 2 版深色横条，`qa/reference-selected.png`。原始文件：`/Users/null/Documents/Codex/2026-10-16/chrome-chatgpt-chat/outputs/timezone-horizontal-dates.png`。
- 原生实现：`qa/widget-final.png`（基础时钟）、`qa/widget-weather.png`（最终天气版本）、`qa/widget-weather-popover.png`（展开面板）。使用 NSHostingView 实际渲染的截图，非设计图替代。
- 视口：桌面组件 720 × 210 pt，2 倍像素密度；展开面板 286 × 450 pt（4 个地区并开启天气）。
- 同一时间：2026-10-16T20:42:00Z；本地时区 America/New_York；纽约、伦敦、上海、东京；深色模式。
- 截图中的天气使用明确的展示数据（18°C 多云、12°C 阴、21°C 晴、17°C 小雨）。实际应用已另行联网验证四城当前天气；交付应用使用系统实时时间和在线天气，未启用展示模式。
- 全图合并比较：`qa/comparison-initial.png`、`qa/comparison-final.png`、`qa/comparison-weather.png`，上方设计稿、下方原生实现，裁切到相同组件区域。
- 1440 px 宽的合并比较中，字体、日期、天气和细分隔线均可读，无需另行放大局部裁切。

## 发现与修复记录

1. 初次比较发现 P2：底色偏浅、数字字重偏重、内容垂直位置偏低。证据 `qa/comparison-initial.png`。已增加石墨色背景浓度、将时间字重调为 regular，并调整内容上下间距。修复证据 `qa/comparison-final.png`。
2. 天气扩展的展开面板首次检查发现 P2：材料背景受外部白色区域影响，呈浅灰色。已加入深色背景和一致的深色外观。最终原生截图 `qa/widget-weather-popover.png` 已复核，无该问题。
3. 用户后续增加天气和状态栏需求：天气图标、温度与状况替换原昼夜图标槽；标题栏增加查看全部时钟的地球按钮。此为需求扩展，保留原卡片尺寸、时间/日期层级、分隔线和圆角。证据 `qa/comparison-weather.png`。

## 五项视觉检查

- 字体：使用原生系统字体、等宽数字；时间 regular，城市 medium。中文、完整年月日、星期、时差和天气均无换行或裁切。
- 间距和布局：四列等宽，时间和日期对齐，圆角、细边框、分隔线及标题层级一致。单地区自动缩为 220 × 210 pt；全部取消桌面勾选时显示有操作指引的空状态。
- 颜色：深色石墨背景，暖白时间文字、次级灰色日期，暖金/浅蓝天气图标。展开面板采用相同色系。
- 图像与图标：全部使用清晰的 SF Symbols。设计图中的桌面壁纸不是应用内容；材质会随用户桌面变化，属于预期差异。未把截图或模拟壁纸贴入应用。
- 文案：每个地区有自己的公历年月日；跨日显示前日/次日；天气按显示的城市查询。状态栏单个和多个地区均保留年月日与时间；过期天气有“未更新”提示。

## 验证

- 31 项可执行检查通过，覆盖日期、夏令时、跨年/闰日、日期变更线、半小时/45 分钟时区、城市搜索，以及天气解析、缺失数据、负温度、WMO 天气码和缓存失效。
- 使用原生界面验证：打开管理地区、中文/英文搜索、添加/移除/排序、无结果提示、桌面与状态栏分别勾选、一个/三个/四个桌面时钟、空状态、完成、恢复默认、置顶及锁定。
- 实际退出并重新打开应用，桌面和状态栏的不同选择被保留。检查后恢复默认 4 个桌面地区、仅本地状态栏时钟。
- 在线天气验证：实际界面读取纽约、伦敦、上海、东京的温度和天气；时钟仍正常刷新。
- 展开面板通过桌面的“查看全部时钟”按钮打开，完整日期/时间/天气与设置入口均可见；面板中选择伦敦后，设置页同步勾选。
- 原生状态栏按钮截图和实际标题记录：`qa/status-local-status.png` / `qa/status-local-state.json`，以及 `qa/status-multiple-status.png` / `qa/status-multiple-state.json`。分别验证 `2026/10/16 16:42 18°C` 和纽约、伦敦两组完整日期时间温度。
- 编译成功，应用完成本地签名。直接点击物理状态栏按钮的位置未由自动化截取；该按钮绑定同一展开动作，展开界面已通过桌面入口验证。窄屏换行和多显示器切换未单独实机覆盖。

## 剩余差异与实现清单

- P3：原图属于图像设计稿，原生字体抗锯齿、SF Symbols 的太阳/月亮笔形和材料背景会有少量像素差异，接受。
- 无待修复的 P0/P1/P2 项。
- 已完成：日期和天气展示、独立选择显示时钟、设置持久化、原生展开面板、视觉修复及复核。


## Meridian 1.1.0 follow-up

- Default-English native desktop screenshot: `docs/assets/widget.png`. Chinese language switching was also verified through the native Settings tab.
- Replaced the NSPopover with a separately sized borderless panel. Native rendered panel `docs/assets/widget-popover.png` was checked through computer-use screenshots: all four rows, heading, weather control and footer remained visible with no hosting-view offset. The clock list scrolls when constrained by screen height.
- Three geometry checks cover top/right margins, a short screen, and a secondary display with negative coordinates. All 44 model, weather, language, configuration and geometry checks pass.
- The program icon replaces the menu bar globe. AppIcon.icns and all native icon sizes are generated from the same transparent source.
- The English GitHub Pages home screen was rendered in a browser. Local assets and JavaScript syntax were checked. English and Chinese marketing images were visually inspected; their screenshot dates/times and product names are consistent.
- Signed archive verification and production update delivery remain separate release checks. No live update is claimed until an owner supplies the release signing seed and publishes the first signed release.
- Pages deployment requires the repository owner to choose GitHub Actions in Pages settings; the available REST identity is read-only for this repository.
