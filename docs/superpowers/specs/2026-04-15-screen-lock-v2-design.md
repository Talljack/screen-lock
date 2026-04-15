# ScreenLock v2 Enhancement Design

**Date:** 2026-04-15
**Status:** Approved
**Base:** v1 design at `2026-04-15-screen-lock-design.md`

## Overview

Five enhancement modules for ScreenLock:

1. Bug fix: cross-day scheduling logic
2. Lock screen animations + built-in dynamic backgrounds (Core Animation)
3. Copy/text system: per-theme defaults + random pool
4. Missing features: auto-start (SMAppService), permission onboarding, custom time input, sound cues
5. README

## Module 1: Cross-Day Bug Fix

**Problem:** `ScheduleManager.parseTime` shifts lockTime to tomorrow when current time has passed it, but `warningTime = lockTime - warningMinutes` is computed separately without accounting for this shift. Edge case: lockTime 00:00 with 30min warning at 23:35 — warningTime could end up as tomorrow's 23:30.

**Fix:** Compute warningTime from the already-resolved lockTime (which already accounts for tomorrow rollover), not independently.

## Module 2: Animations + Dynamic Backgrounds

### 2a. Window Animations
- Fade-in: `alphaValue` 0→1 over 0.6s
- Card spring entrance: `CASpringAnimation` on `transform.translation.y`
- Countdown pulse: subtle scale oscillation each second

### 2b. Built-in Dynamic Backgrounds (Core Animation, GPU-accelerated)

| Theme | Effect |
|-------|--------|
| peachBunny | CAEmitterLayer: pink heart + petal particles floating up; gradient breathing (brightness oscillation) |
| cloudPudding | 3-5 white rounded CALayers drifting horizontally; occasional star twinkle (opacity animation) |
| starlightCat | Random star twinkle (opacity) + shooting stars (CAKeyframeAnimation on bezier path) |

### 2c. User Custom Override
- User-selected static image disables dynamic effects
- Menu option "使用主题动态背景" restores built-in animation

## Module 3: Copy System

### Per-Theme Defaults
- peachBunny (可爱): "先休息一下下" / "给眼睛、肩膀和脑袋一个可爱的暂停键" / "喝口水 / 伸个懒腰 / 看看远处"
- cloudPudding (温柔): "今天已经很棒了" / "睡眠是最好的充电器" / "闭上眼睛 / 深呼吸三次 / 和今天说晚安"
- starlightCat (诗意): "星星也要休息了" / "夜深了，把未完成的事交给明天的自己" / "月亮替你值班 / 明天又是元气满满的一天"

### Random Pool
- 3-5 candidate sets per theme
- Random selection each lock event
- User custom copy takes priority over random pool

### Menu Changes
- Theme switch auto-updates copy (unless user has customized)
- Track `isCustomCopy` flag in Settings

## Module 4: Missing Features

### 4a. App Icon
- Create Assets.xcassets with AppIcon placeholder

### 4b. Auto-Start (SMAppService)
- Raise deployment target to macOS 13
- Menu toggle "开机自启动"
- `SMAppService.mainApp.register()` / `unregister()`

### 4c. Custom Lock Time Input
- "自定义时间..." menu item
- NSAlert with HH:mm text field

### 4d. Permission Onboarding
- First launch: check accessibility permission via `AXIsProcessTrusted()`
- Show friendly Chinese-language alert with instructions
- Persist `hasShownPermissionGuide` flag

### 4e. Sound Cues
- Warning start: `NSSound(named: "Tink")?.play()`
- Lock countdown end: `NSSound(named: "Glass")?.play()`
- System built-in sounds, no external resources

## Module 5: README
- Project description, features, build instructions, architecture overview
