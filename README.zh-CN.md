<p align="center"><img src="docs/assets/app-icon.png" width="112" alt="Meridian 应用图标"></p>
<h1 align="center">Meridian · 子午线时钟</h1>
<p align="center"><strong>世界此刻，一眼尽览。</strong><br>Mac 桌面与状态栏上的多时区时钟、完整日期和当地天气。</p>
<p align="center"><a href="https://etongle.github.io/Meridian/?lang=zh">官网</a> · <a href="https://github.com/etongle/Meridian/releases">发布版本</a> · <a href="README.md">English</a></p>

![Meridian 中文宣传图](docs/assets/promo-zh.png)

## 主要功能

- 每个地区显示完整年月日、星期和 24 小时制时间，跨日标注“前日 / 次日”。
- 默认约 4 个地区，最多 6 个；桌面和状态栏分别选择一个或多个时钟。
- 深色桌面横条支持拖动、置顶、锁定位置与隐藏。
- 点击状态栏的应用图标展开全部地区；面板定位在屏幕内，小屏幕可以滚动查看。
- 显示天气图标、摄氏温度和天气状况，每 15 分钟更新。
- 默认英文，可在设置中即时切换简体中文。
- 已集成 Sparkle，支持自动检查及可选的后台下载；签名更新渠道在首个配置完成的正式版本发布后启用。

![实际应用截图，使用示例时间与天气](docs/assets/widget.png)

## 使用

需要 **macOS 14 或更新版本**。当前本机构建为 Apple Silicon；发布流程会编译 Apple Silicon 与 Intel 通用版本。

1. 从 [Releases](https://github.com/etongle/Meridian/releases) 获取版本，或自行构建。
2. 将 `Meridian.app` 拖入“应用程序”并打开。
3. 点右上角 **+** 管理地区，分别勾选 **Desktop / 桌面** 与 **Menu bar / 状态栏**。
4. 点击状态栏左侧的应用图标查看全部地区，**More / 更多** 中可调整位置、检查更新或退出。
5. 在 **Settings / 设置** 中切换语言、天气和更新选项。

本地时钟跟随系统时区。日期采用 `YYYY/MM/DD`，设置和位置会自动保存。保留原型版本的应用标识，以延续已有配置。

## 天气与隐私

天气由 [Open-Meteo](https://open-meteo.com/) 提供，默认免费接口用于非商业使用。按时钟所示城市查询，本地使用系统时区对应的城市，不申请设备定位权限。

网络异常不影响时钟。天气缺失或缓存过期会明确标出，也可以关闭天气；关闭后太阳和月亮仅表示当地白天或夜间时段。

## 构建

安装 Apple Command Line Tools 或 Xcode 后执行：

```sh
zsh build.sh
zsh test.sh
```

产物为 `dist/Meridian.app`。构建会下载固定版本 Sparkle 2.10.0 并校验 SHA-256，开发版本使用本地签名。

编译通用版本：

```sh
MERIDIAN_ARCHS="arm64 x86_64" zsh build.sh
```

检查覆盖完整日期、夏令时、跨年、半小时/45 分钟时区、天气、国际化、更新配置与下拉面板定位。

## 官网与自动更新

`docs/` 是默认英文、可切换中文的 GitHub Pages 官网。发布流程及签名配置见 [RELEASING.md](RELEASING.md)。没有更新公钥的本地版本不会访问未就绪的更新渠道，设置页会显示说明。

[应用图标与中英文宣传图](BRAND.md) 已包含在仓库中。第三方授权及天气接口说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
