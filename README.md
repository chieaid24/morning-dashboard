# Morning Dashboard

Press Ctrl+Alt+M on Windows 11 and this AutoHotkey v2 daemon opens your morning layout across two monitors; press it again and it closes only the windows it created.

```text
LEFT MONITOR                    RIGHT MONITOR
+---------------------+        +----------+-----------+
|       Outlook       |        |  Google  |  Weekly   |
| (Gmail Brave window |        | Calendar | schedule  |
|  maximized beneath) |        |          |  image    |
+---------------------+        +----------+-----------+
```

Closing Outlook by hand reveals the already-maximized Gmail window with your three inboxes. The schedule image stays in the gitignored `.private/` folder and never reaches Git history; a pre-commit hook, `scripts\verify-privacy.ps1`, and CI all enforce this.

## Installation

Requires Windows 11, two monitors, Brave, and Outlook. The installer fetches AutoHotkey v2 and PowerToys with winget when missing.

1. Clone this repository.

   ```powershell
   git clone https://github.com/chieaid24/morning-dashboard.git
   ```

2. Run the installer with your schedule image.

   ```powershell
   .\scripts\install.ps1 -ScheduleImagePath "C:\Users\you\Pictures\schedule.jpg"
   ```

The hotkey daemon starts immediately and registers itself in your Startup folder.

## Configuration

The installer writes a gitignored `config.local.ini` with your discovered paths. Edit it to change the hotkey, Gmail tab URLs and order, Calendar account, Brave profile, classic vs new Outlook, or monitor selection (blank means auto-detect by work-area position). Update the schedule image with `.\scripts\set-schedule-image.ps1 -Path "C:\path\to\new.jpg"` and remove everything with `.\scripts\uninstall.ps1`.
