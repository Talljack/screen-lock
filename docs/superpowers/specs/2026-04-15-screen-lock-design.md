# ScreenLock - macOS Sleep Health App Design

**Date:** 2026-04-15  
**Status:** Approved  
**Tech Stack:** Swift + AppKit

## Overview

ScreenLock is a macOS menu bar application designed to help developers maintain healthy sleep habits by enforcing scheduled screen lockdown. The app provides three core features:

1. **Scheduled Screen Lock** - Automatically locks the screen and turns off the display at a user-defined time
2. **Pre-Lock Screen Dimming** - Gradually reduces brightness and applies warm color filter before lockdown
3. **Lid-Closed No-Sleep** - Prevents system sleep when the laptop lid is closed, allowing background processes to continue

## User Problem

Developers often work late into the night and lose track of time. This app acts as a "digital bedtime enforcer" by:
- Forcing screen lockdown at a set time (e.g., midnight)
- Providing gentle visual warnings before lockdown (dimming + warm colors)
- Allowing background tasks to continue running even when the lid is closed

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────┐
│                      MenuBarController                   │
│                    (User Interface)                      │
└────────────┬────────────────────────────────────────────┘
             │
             ├──────────┬──────────┬──────────┬────────────┐
             │          │          │          │            │
        ┌────▼───┐ ┌───▼────┐ ┌──▼─────┐ ┌──▼────────┐   │
        │Schedule│ │ Screen │ │ Power  │ │ Settings  │   │
        │Manager │ │Manager │ │Manager │ │ Manager   │   │
        └────┬───┘ └───┬────┘ └──┬─────┘ └──┬────────┘   │
             │         │          │           │            │
             │    ┌────▼──────────▼───────────▼────┐       │
             └────►   macOS System APIs            │       │
                  │  (IOKit, CoreGraphics, etc)    │       │
                  └────────────────────────────────┘       │
```

### Module Responsibilities

**AppDelegate**
- Application entry point
- Initializes all managers and menu bar controller
- Handles app lifecycle (launch, terminate)

**MenuBarController**
- Displays icon in system menu bar
- Provides dropdown menu with:
  - Current status and countdown display
  - Lock time picker (HH:MM format)
  - Warning duration picker (minutes before lock)
  - Lid-closed no-sleep toggle
  - Quit option
- Updates menu icon based on app state (normal/warning/locked)

**ScheduleManager**
- Calculates warning time and lock time based on user settings
- Runs `Timer` that checks current time every minute
- Triggers events:
  - Warning time reached → notify ScreenManager to start dimming
  - Lock time reached → trigger screen lock and display off
- Handles cross-day scenarios (e.g., lock at 2:00 AM)

**ScreenManager**
- Controls screen brightness using `CGDisplaySetDisplayTransferByFormula`
- Applies warm color filter by adjusting RGB channel ratios
- Implements gradual transition (30-60 steps over warning period)
- Executes screen lock and display shutdown at lock time

**PowerManager**
- Creates `IOPMAssertionTypePreventUserIdleSystemSleep` assertion on app launch
- Prevents system sleep when lid is closed
- Releases assertion on app quit
- Always active when app is running

**SettingsManager**
- Persists user settings to `~/Library/Application Support/ScreenLock/settings.json`
- Settings include:
  - Lock time (HH:MM)
  - Warning duration (minutes)
  - Lid-closed no-sleep enabled (boolean)
- Loads settings on app launch
- Saves immediately when settings change

## Data Flow

### Normal Operation Flow

1. User sets lock time to `00:00` and warning duration to `30 minutes` via menu bar
2. SettingsManager saves to JSON file
3. ScheduleManager calculates:
   - Warning time: `23:30`
   - Lock time: `00:00`
4. Timer checks every minute:
   - At `23:30`: ScheduleManager → ScreenManager starts gradual dimming + warm filter
   - At `00:00`: ScheduleManager → ScreenManager locks screen and turns off display
5. PowerManager maintains sleep prevention throughout

### State Transitions

```
Normal State (before warning time)
    ↓ (warning time reached)
Warning State (dimming + warm colors active)
    ↓ (lock time reached)
Locked State (screen off, system locked)
    ↓ (user unlocks manually)
Normal State (reset for next day)
```

## Technical Implementation

### Key APIs

**1. Prevent Lid-Closed Sleep**
```swift
var assertionID: IOPMAssertionID = 0
IOPMAssertionCreateWithName(
    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "ScreenLock - Prevent Sleep" as CFString,
    &assertionID
)
```

**2. Screen Brightness & Color Adjustment**
```swift
CGDisplaySetDisplayTransferByFormula(
    displayID,
    redMin, redMax, redGamma,      // Adjust for brightness
    greenMin, greenMax, greenGamma, // Adjust for brightness
    blueMin, blueMax, blueGamma     // Reduce blue for warm tone
)
```

Dimming: Reduce all RGB max values proportionally  
Warm filter: Increase red ratio, decrease blue ratio

**3. Lock Screen & Turn Off Display**
```swift
// Lock screen
let task = Process()
task.launchPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
task.arguments = ["-suspend"]
task.launch()

// Turn off display
IODisplayWrangler API or pmset command
```

### Project Structure

```
ScreenLock/
├── ScreenLock.xcodeproj
├── ScreenLock/
│   ├── App/
│   │   ├── AppDelegate.swift          # App entry point
│   │   ├── Info.plist                 # Bundle config
│   │   └── Assets.xcassets            # Icons (moon, clock)
│   ├── Controllers/
│   │   └── MenuBarController.swift    # Menu bar UI
│   ├── Managers/
│   │   ├── ScheduleManager.swift      # Timer & scheduling
│   │   ├── ScreenManager.swift        # Display control
│   │   ├── PowerManager.swift         # Sleep prevention
│   │   └── SettingsManager.swift      # Persistence
│   └── Models/
│       └── Settings.swift             # Settings data model
```

### Settings Data Model

```swift
struct Settings: Codable {
    var lockTime: String           // "00:00" format
    var warningMinutes: Int        // e.g., 30
    var preventSleepEnabled: Bool  // Always true when app runs
}
```

### Menu Bar UI

**Menu Items:**
- Status: "距离锁屏还有 2小时30分钟" (dynamic countdown)
- Separator
- "设置锁屏时间: [00:00]" (time picker)
- "提前警告时间: [30分钟]" (duration picker)
- "合盖不休眠: [✓]" (toggle, always on)
- Separator
- "退出 ScreenLock"

**Icon States:**
- Normal: Moon icon (gray)
- Warning: Moon icon (orange)
- Locked: Moon icon (red)

## Error Handling

### Permission Issues
- **Problem**: App lacks accessibility or automation permissions
- **Solution**: Show alert on first launch with instructions to grant permissions in System Preferences → Security & Privacy → Privacy → Accessibility/Automation
- **Fallback**: Display warning icon in menu bar if permissions denied

### Settings File Corruption
- **Problem**: JSON file is corrupted or unreadable
- **Solution**: Use default settings (lock at 00:00, 30min warning)
- **Recovery**: Overwrite corrupted file with defaults on next save

### API Call Failures
- **Problem**: `IOPMAssertionCreateWithName` or display control APIs fail
- **Solution**: Log error, show "功能不可用" status in menu
- **Behavior**: App continues running but affected feature is disabled

### Cross-Day Time Calculation
- **Problem**: Determining if lock time is today or tomorrow
- **Logic**:
  - If current time < lock time: schedule for today
  - If current time >= lock time: schedule for tomorrow
  - Recalculate after each lock event

## System Requirements

- **macOS Version**: 10.15 (Catalina) or later
- **Permissions Required**:
  - Accessibility (for screen control)
  - Automation (for screen lock)
- **Bundle Configuration**:
  - `LSUIElement = YES` (hide Dock icon, menu bar only)
  - Sandbox disabled (requires system API access)
  - Bundle ID: `com.yourname.screenlock`

## User Experience Flow

### First Launch
1. App starts, menu bar icon appears
2. Alert prompts user to grant Accessibility and Automation permissions
3. User opens System Preferences and grants permissions
4. App detects permissions granted, shows "Ready" status

### Daily Usage
1. User clicks menu bar icon
2. Sets lock time (e.g., 00:00) and warning duration (e.g., 30min)
3. App shows countdown: "距离锁屏还有 X小时X分钟"
4. At 23:30: Screen gradually dims and warms over 30 minutes
5. At 00:00: Screen locks and turns off
6. User manually unlocks when ready to work again
7. Cycle repeats next day

### Lid-Closed Behavior
- User closes laptop lid while app is running
- System does NOT sleep (PowerManager prevents it)
- Background processes (builds, downloads, servers) continue running
- User can reopen lid anytime without interruption

## Non-Goals (Out of Scope)

- Multiple lock schedules (weekday/weekend)
- Snooze or override functionality
- Activity tracking or statistics
- Integration with calendar or other apps
- Custom notification sounds
- Remote control or API

## Success Criteria

- App successfully prevents sleep when lid is closed
- Screen dims and warms gradually during warning period
- Screen locks and turns off at scheduled time
- Settings persist across app restarts
- Menu bar UI is responsive and intuitive
- App uses minimal system resources (<50MB RAM, <1% CPU idle)

## Future Enhancements (Not in Initial Release)

- Multiple schedules (weekday/weekend profiles)
- Smart scheduling based on calendar events
- Gradual wake-up with screen brightening
- Statistics dashboard (sleep time tracking)
- Notification center integration
