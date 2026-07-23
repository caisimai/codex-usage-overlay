# Codex Usage Overlay

一个可快速复用的 macOS Codex 额度悬浮窗。它把当前 Codex 账号的剩余额度显示在 ChatGPT/Codex 客户端左下角用户名上方，效果类似截图中的红色标注区域。

## 特性

- 使用 Codex 内置 `codex app-server` 的 `account/rateLimits/read`；
- 优先处理可用的 `account/rateLimits/updated` 通知；
- 每 3 分钟兜底刷新一次，切回 Codex 时立即刷新，不因悬浮窗移动或倒计时重绘而请求额度；
- 在用户名同行右侧显示紧凑的“周额度剩余 XX%”标签；
- 最小化和恢复时使用淡出/淡入动画，不遮挡上方个人信息区域；
- `resetsAt` 倒计时在本地计算；
- 使用 macOS Accessibility API 跟随用户名/头像行；
- 位置检查采用 Accessibility 事件驱动，静止时不轮询窗口位置；
- 找不到辅助功能元素时回退到左下角固定位置；
- 不修改、不重签 ChatGPT.app/Codex.app；
- 不读取或持久化 Token、Cookie、邮箱或使用历史；
- 可通过 LaunchAgent 登录时自动启动。

## 快速安装

要求：macOS 13+、Swift/Xcode Command Line Tools，以及已登录 ChatGPT/Codex 客户端。

```bash
git clone https://github.com/your-org/codex-usage-overlay.git
cd codex-usage-overlay
./scripts/install.sh
```

第一次启动时，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `Codex Usage Overlay`。没有该权限时仍会显示，但使用保守的固定位置。

如果客户端没有暴露容易识别的用户名 Accessibility 文本，可以指定锚点关键词：

```bash
CODEX_USAGE_PROFILE_TEXT="simon" ./scripts/install.sh
```

卸载：

```bash
./scripts/uninstall.sh
```

## 架构

```text
Codex/ChatGPT 登录上下文
          ↓
内置 codex app-server --stdio
          ↓ JSON-RPC
account/rateLimits/read
          ↓
Swift 额度解析器
          ↓
NSPanel 悬浮窗 + Accessibility 定位
```

客户端更新不覆盖这个伴侣 App，但如果 App Server 协议或客户端 Accessibility 树发生变化，需要重新发布该项目版本。

## 安全边界

本项目只使用额度读取接口，不调用 `account/rateLimitResetCredit/consume`。App Server 自己管理登录上下文；本项目不直接解析 `~/.codex/auth.json`，也不向网络发送自己的凭据。

## 开发

```bash
swift test
swift build -c release
```

这是非官方独立项目，不代表 OpenAI、ChatGPT 或 Codex 官方立场。
