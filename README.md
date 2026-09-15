# Morning Dashboard

Press Ctrl+Alt+M to open my morning layout across two monitors (Gmail, Outlook, Google Calendar, image of weekly plan). Press it again and it cleanly stops the dashboard.

## Installation

Req. Windows 11, Brave, Outlook. The installer fetches AutoHotkey v2 and PowerToys with winget when missing.

1. Clone this repository.

   ```powershell
   git clone https://github.com/chieaid24/morning-dashboard.git
   ```

2. Run the installer with a schedule image of your choice.

   ```powershell
   .\scripts\install.ps1 -ScheduleImagePath "C:\Users\you\Pictures\schedule.jpg"
   ```
