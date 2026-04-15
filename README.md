# ScreenLock

macOS 菜单栏应用，帮助开发者养成健康的睡眠习惯。到点自动锁屏，提前渐进提醒，合盖不休眠。

## 功能

- **定时锁屏** — 设定每日锁屏时间（预设 22:00–02:00 或自定义任意时间），到时间后显示全屏休息倒计时，倒计时结束自动锁定系统
- **渐进警告** — 锁屏前 N 分钟开始逐步降低屏幕亮度并添加暖色滤镜，温柔提醒你该休息了
- **强制休息** — 全屏覆盖窗口，无法关闭，倒计时 1–30 分钟可自定义
- **三套可爱主题** — 蜜桃兔兔 🐰 / 云朵布丁 ☁️ / 星星晚安 🌟，各有专属配色、动态背景和文案
- **动态背景** — Core Animation 粒子效果：心形飘浮、云朵飘动、星星闪烁 + 流星划过
- **随机文案** — 每个主题 4 组可爱文案随机展示，也支持完全自定义
- **合盖不休眠** — 关闭笔记本盖子后保持系统运行，后台任务不中断
- **开机自启动** — 一键设置，开机即守护
- **首次启动引导** — 自动检测辅助功能权限，引导用户开启

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- 需要辅助功能权限（首次启动会自动引导）

## 构建

```bash
git clone <repo-url>
cd screen-lock
open ScreenLock.xcodeproj
# Xcode → Product → Build (⌘B)
```

无第三方依赖，纯 Swift + AppKit + Core Animation。

## 项目结构

```
ScreenLock/
├── App/
│   ├── AppDelegate.swift          # 应用入口 + 权限引导
│   ├── main.swift
│   └── Info.plist
├── Controllers/
│   ├── MenuBarController.swift    # 菜单栏 UI
│   ├── LockScreenWindow.swift     # 全屏锁屏窗口 + 动画
│   └── DynamicBackgroundView.swift # 动态粒子背景
├── Managers/
│   ├── ScheduleManager.swift      # 定时调度
│   ├── ScreenManager.swift        # 屏幕亮度/Gamma 控制
│   ├── PowerManager.swift         # 合盖不休眠 (IOKit)
│   └── SettingsManager.swift      # 设置持久化
└── Models/
    └── Settings.swift             # 数据模型 + 主题文案
```

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | AppKit (NSMenu, NSWindow, NSVisualEffectView) |
| 动画 | Core Animation (CAEmitterLayer, CASpringAnimation, CAKeyframeAnimation) |
| 屏幕控制 | CoreGraphics (CGSetDisplayTransferByFormula) |
| 防休眠 | IOKit (IOPMAssertionCreateWithName) |
| 自启动 | ServiceManagement (SMAppService) |
| 持久化 | Foundation (JSONEncoder/JSONDecoder) |
