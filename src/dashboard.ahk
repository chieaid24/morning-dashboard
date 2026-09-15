#Requires AutoHotkey v2.0
#SingleInstance Force

; Morning Dashboard hotkey daemon.
; One hotkey toggles a two-monitor layout: Outlook maximized over a Gmail
; Brave window on the left monitor, Google Calendar and a private schedule
; viewer split 50/50 on the right monitor. Teardown closes only windows the
; dashboard created and restores a borrowed Outlook window.

; Per-monitor DPI awareness so work-area math matches physical pixels on
; mixed-DPI monitor setups. Best effort on older Windows builds.
try DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

SplitPath A_ScriptDir, , &repoRoot
global RepoRoot := repoRoot
global StateFile := RepoRoot "\.state\session.ini"
global DashboardBusy := false

GroupAdd "MD_Outlook", "ahk_exe olk.exe"
GroupAdd "MD_Outlook", "ahk_exe OUTLOOK.EXE"

SetupTray()
RegisterHotkey()
HandleArgs()
return

; ---------------------------------------------------------------- lifecycle

SetupTray() {
    A_IconTip := "Morning Dashboard"
    try TraySetIcon(RepoRoot "\assets\dashboard.ico")
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Open Morning Dashboard", (*) => Guard(OpenDashboard))
    tray.Add("Close Morning Dashboard", (*) => Guard(CloseDashboard))
    tray.Add("Toggle Morning Dashboard", (*) => Guard(ToggleDashboard))
    tray.Add()
    tray.Add("Exit (until next login)", (*) => ExitApp())
    tray.Default := "Toggle Morning Dashboard"
}

RegisterHotkey() {
    hk := Cfg("General", "Hotkey", "^!m")
    try Hotkey(hk, (*) => Guard(ToggleDashboard))
    catch as err
        TrayNote("Could not register hotkey '" hk "': " err.Message)
}

HandleArgs() {
    if !A_Args.Length
        return
    switch StrLower(A_Args[1]) {
        case "open": Guard(OpenDashboard)
        case "close": Guard(CloseDashboard)
        case "toggle": Guard(ToggleDashboard)
    }
}

; Serializes open/close so repeated hotkey presses cannot run concurrently.
Guard(action) {
    global DashboardBusy
    if DashboardBusy
        return
    DashboardBusy := true
    try action()
    finally DashboardBusy := false
}

ToggleDashboard() {
    if StateActive()
        CloseDashboard()
    else
        OpenDashboard()
}

; ------------------------------------------------------------------- config

; The Windows INI APIs (IniRead/IniWrite) fail on some network paths
; (e.g. \\wsl.localhost), so all INI access uses plain file reads/writes.
IniLoad(path) {
    data := Map()
    section := ""
    try content := FileRead(path)
    catch
        return data
    loop parse content, "`n", "`r" {
        line := Trim(A_LoopField)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue
        if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
            section := SubStr(line, 2, StrLen(line) - 2)
            continue
        }
        pos := InStr(line, "=")
        if !pos
            continue
        data[section "." Trim(SubStr(line, 1, pos - 1))] := Trim(SubStr(line, pos + 1))
    }
    return data
}

ConfigPath() {
    for p in [RepoRoot "\config.local.ini", RepoRoot "\config\config.local.ini"]
        if FileExist(p)
            return p
    return RepoRoot "\config\config.example.ini"
}

Cfg(section, key, default := "") {
    global ConfigCache, ConfigCachePath, ConfigCacheTime
    path := ConfigPath()
    t := ""
    try t := FileGetTime(path)
    if !IsSet(ConfigCache) || ConfigCachePath != path || ConfigCacheTime != t {
        ConfigCache := IniLoad(path)
        ConfigCachePath := path
        ConfigCacheTime := t
    }
    k := section "." key
    return ConfigCache.Has(k) && ConfigCache[k] != "" ? ConfigCache[k] : default
}

; ------------------------------------------------------------ session state

StateWrite(key, value) {
    DirCreate RepoRoot "\.state"
    data := IniLoad(StateFile)
    data["Session." key] := value
    out := "[Session]`n"
    for k, v in data
        if SubStr(k, 1, 8) = "Session."
            out .= SubStr(k, 9) "=" v "`n"
    f := FileOpen(StateFile, "w")
    f.Write(out)
    f.Close()
}

StateRead(key, default := "") {
    data := IniLoad(StateFile)
    k := "Session." key
    return data.Has(k) && data[k] != "" ? data[k] : default
}

StateReadInt(key) {
    v := StateRead(key, "0")
    return IsInteger(v) ? Integer(v) : 0
}

StateClear() {
    try FileDelete StateFile
}

StateActive() {
    return StateRead("Active", "0") = "1"
}

; ----------------------------------------------------------------- monitors

; Left = smallest work-area center X, right = largest. Coordinates can be
; negative. config.local.ini [Monitors] overrides by AutoHotkey index.
PickMonitors(&leftMon, &rightMon) {
    count := MonitorGetCount()
    if count < 2
        return false
    leftMon := rightMon := 1
    minCx := maxCx := ""
    loop count {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        cx := (l + r) / 2
        if minCx = "" || cx < minCx {
            minCx := cx
            leftMon := A_Index
        }
        if maxCx = "" || cx > maxCx {
            maxCx := cx
            rightMon := A_Index
        }
    }
    cfgL := Cfg("Monitors", "LeftMonitor")
    cfgR := Cfg("Monitors", "RightMonitor")
    if cfgL != "" && IsInteger(cfgL)
        leftMon := Integer(cfgL)
    if cfgR != "" && IsInteger(cfgR)
        rightMon := Integer(cfgR)
    return leftMon != rightMon
}

; ---------------------------------------------------------- window plumbing

SnapshotWindows(winTitle) {
    seen := Map()
    for hwnd in WinGetList(winTitle)
        seen[hwnd] := true
    return seen
}

; Returns the first window of winTitle not present in `before`, preferring
; one whose title contains `needle`. 0 on timeout.
WaitNewWindow(winTitle, before, needle := "", timeoutMs := 30000, excludeClass := "") {
    deadline := A_TickCount + timeoutMs
    fallback := 0
    while A_TickCount < deadline {
        for hwnd in WinGetList(winTitle) {
            if before.Has(hwnd)
                continue
            if excludeClass != "" && WindowHasClass(hwnd, excludeClass)
                continue
            if needle = ""
                return hwnd
            title := ""
            try title := WinGetTitle("ahk_id " hwnd)
            if InStr(title, needle)
                return hwnd
            if !fallback
                fallback := hwnd
        }
        Sleep 250
    }
    return fallback
}

WindowHasClass(hwnd, cls) {
    c := ""
    try c := WinGetClass("ahk_id " hwnd)
    return c = cls
}

MoveWindowTo(hwnd, x, y, w, h) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    if WinGetMinMax("ahk_id " hwnd) != 0
        WinRestore "ahk_id " hwnd
    WinMove x, y, w, h, "ahk_id " hwnd
}

; Closes hwnd only if it still exists and belongs to an expected executable.
SafeCloseWindow(hwnd, expectedExes) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    exe := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    match := false
    for e in expectedExes
        if StrLower(exe) = StrLower(e)
            match := true
    if !match
        return
    try WinClose "ahk_id " hwnd, , 5
}

; -------------------------------------------------------------------- brave

BraveExe() {
    exe := Cfg("Brave", "Executable")
    if exe != "" && FileExist(exe)
        return exe
    candidates := [
        "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
        EnvGet("LOCALAPPDATA") "\BraveSoftware\Brave-Browser\Application\brave.exe"
    ]
    for p in candidates
        if FileExist(p)
            return p
    throw Error("Brave not found. Set [Brave] Executable in config.local.ini.")
}

; New-window HWNDs are found by diffing top-level Brave windows before and
; after launch; Chromium shares processes, so PIDs cannot identify windows.
LaunchBraveWindow(args, titleNeedle) {
    before := SnapshotWindows("ahk_exe brave.exe")
    cmd := '"' BraveExe() '"'
    prof := Cfg("Brave", "ProfileDirectory")
    if prof != ""
        cmd .= ' --profile-directory="' prof '"'
    cmd .= " " args
    Run cmd
    hwnd := WaitNewWindow("ahk_exe brave.exe", before, titleNeedle)
    if !hwnd
        throw Error("New Brave window did not appear (" titleNeedle ").")
    return hwnd
}

FileUrl(path) {
    p := StrReplace(path, "\", "/")
    p := StrReplace(p, " ", "%20")
    return SubStr(p, 1, 2) = "//" ? "file:" p : "file:///" p
}

; ---------------------------------------------------------- dashboard parts

OpenGmailWindow() {
    args := "--new-window"
    for key in ["Url1", "Url2", "Url3"] {
        url := Cfg("Gmail", key)
        if url != ""
            args .= ' "' url '"'
    }
    return LaunchBraveWindow(args, "Gmail")
}

OpenCalendarWindow() {
    url := Cfg("Calendar", "Url", "https://calendar.google.com/calendar/u/0/r/day")
    return LaunchBraveWindow('--app="' url '"', "Calendar")
}

OpenScheduleWindow() {
    viewer := RepoRoot "\" Cfg("Schedule", "Viewer", "viewer\schedule.html")
    if !FileExist(viewer)
        throw Error("Schedule viewer not found: " viewer)
    img := RepoRoot "\" Cfg("Schedule", "LocalImage", ".private\WEEKLY SCHEDULE.jpg")
    if !FileExist(img)
        TrayNote("Schedule image missing. Run scripts\set-schedule-image.ps1.")
    return LaunchBraveWindow('--app="' FileUrl(viewer) '"', "Morning Dashboard Schedule")
}

; Skips #32770 dialogs (reminders, error prompts) - only a real main window
; should be reused or tracked.
FindOutlookMainWindow() {
    for hwnd in WinGetList("ahk_group MD_Outlook") {
        if WindowHasClass(hwnd, "#32770")
            continue
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if title != ""
            return hwnd
    }
    return 0
}

LaunchOutlook() {
    prefer := StrLower(Cfg("Outlook", "Prefer", "classic"))
    exe := Cfg("Outlook", "Executable")
    appId := Cfg("Outlook", "AppId")
    if prefer = "new" && appId != "" {
        Run 'explorer.exe "shell:AppsFolder\' appId '"'
        return
    }
    if exe != "" && FileExist(exe) {
        Run '"' exe '"'
        return
    }
    if appId != "" {
        Run 'explorer.exe "shell:AppsFolder\' appId '"'
        return
    }
    Run "outlook.exe"
}

; Reuses an existing Outlook main window (recording its geometry for
; restore-on-teardown) or launches one owned by the dashboard.
AcquireOutlook(&owned, &px, &py, &pw, &ph, &pmm) {
    owned := false
    px := py := pw := ph := pmm := 0
    hwnd := FindOutlookMainWindow()
    if hwnd {
        WinGetPos &px, &py, &pw, &ph, "ahk_id " hwnd
        pmm := WinGetMinMax("ahk_id " hwnd)
        return hwnd
    }
    owned := true
    before := SnapshotWindows("ahk_group MD_Outlook")
    LaunchOutlook()
    hwnd := WaitNewWindow("ahk_group MD_Outlook", before, "", 45000, "#32770")
    if !hwnd
        throw Error("Outlook window did not appear.")
    return hwnd
}

RestoreOutlook(hwnd, x, y, w, h, mm) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    try {
        WinRestore "ahk_id " hwnd
        if w > 0 && h > 0 {
            ; Twice: apps that rescale on a monitor DPI change resize
            ; themselves after the first move; the second pass corrects it.
            WinMove x, y, w, h, "ahk_id " hwnd
            WinMove x, y, w, h, "ahk_id " hwnd
        }
        if mm = 1
            WinMaximize "ahk_id " hwnd
        else if mm = -1
            WinMinimize "ahk_id " hwnd
    }
}

; ----------------------------------------------------------------- layout

PositionRightMonitor(mon, calHwnd, schedHwnd) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    w := r - l, h := b - t, half := w // 2
    MoveWindowVisible(calHwnd, l, t, half, h)
    MoveWindowVisible(schedHwnd, l + half, t, w - half, h)
}

; Positions a window so its VISIBLE frame fills the target rectangle.
; GetWindowRect includes invisible resize borders, so a plain WinMove
; leaves gaps; compensate with the DWM extended frame bounds, like Snap.
MoveWindowVisible(hwnd, x, y, w, h) {
    MoveWindowTo(hwnd, x, y, w, h)
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect)
        return
    ext := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", ext, "uint", 16, "uint")
        return  ; DWMWA_EXTENDED_FRAME_BOUNDS unsupported; keep plain placement
    il := NumGet(ext, 0, "int") - NumGet(rect, 0, "int")
    it := NumGet(ext, 4, "int") - NumGet(rect, 4, "int")
    ir := NumGet(rect, 8, "int") - NumGet(ext, 8, "int")
    ib := NumGet(rect, 12, "int") - NumGet(ext, 12, "int")
    if il || it || ir || ib
        WinMove x - il, y - it, w + il + ir, h + it + ib, "ahk_id " hwnd
}

; Both maximized on the left monitor; Outlook on top, Gmail directly
; beneath so closing Outlook reveals a full-monitor Gmail. Z-order is
; enforced with SetWindowPos because WinActivate can be blocked by
; foreground-lock when the user is interacting with another window.
StackLeftMonitor(mon, gmailHwnd, outlookHwnd) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    MoveWindowTo(gmailHwnd, l, t, r - l, b - t)
    WinMaximize "ahk_id " gmailHwnd
    MoveWindowTo(outlookHwnd, l, t, r - l, b - t)
    WinMaximize "ahk_id " outlookHwnd
    try WinActivate "ahk_id " outlookHwnd
    flags := 0x1 | 0x2 | 0x10  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    DllCall("SetWindowPos", "ptr", outlookHwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
    DllCall("SetWindowPos", "ptr", gmailHwnd, "ptr", outlookHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
}

; ------------------------------------------------------------- open / close

OpenDashboard() {
    if StateActive() {
        TrayNote("Dashboard is already open.")
        return
    }
    if !PickMonitors(&leftMon, &rightMon) {
        TrayNote("Two monitors are required for the Morning Dashboard.")
        return
    }
    created := []
    outlook := 0
    owned := true
    px := py := pw := ph := pmm := 0
    try {
        gmail := OpenGmailWindow()
        created.Push(gmail)
        cal := OpenCalendarWindow()
        created.Push(cal)
        sched := OpenScheduleWindow()
        created.Push(sched)
        outlook := AcquireOutlook(&owned, &px, &py, &pw, &ph, &pmm)
        if owned
            created.Push(outlook)

        PositionRightMonitor(rightMon, cal, sched)
        StackLeftMonitor(leftMon, gmail, outlook)

        StateWrite("GmailHwnd", gmail)
        StateWrite("CalendarHwnd", cal)
        StateWrite("ScheduleHwnd", sched)
        StateWrite("OutlookHwnd", outlook)
        StateWrite("OutlookOwned", owned ? "1" : "0")
        StateWrite("OutlookPrevX", px)
        StateWrite("OutlookPrevY", py)
        StateWrite("OutlookPrevW", pw)
        StateWrite("OutlookPrevH", ph)
        StateWrite("OutlookPrevMinMax", pmm)
        StateWrite("Active", "1")
        TrayNote("Morning Dashboard opened.")
    } catch as err {
        for hwnd in created
            SafeCloseWindow(hwnd, ["brave.exe", "olk.exe", "OUTLOOK.EXE"])
        if outlook && !owned
            RestoreOutlook(outlook, px, py, pw, ph, pmm)
        StateClear()
        LogError("open failed: " err.Message " (" err.What ", line " err.Line ")")
        TrayNote("Dashboard failed to open: " err.Message)
    }
}

; Closes only tracked dashboard windows; skips any the user already closed.
CloseDashboard() {
    if !StateActive() {
        TrayNote("Dashboard is not open.")
        return
    }
    SafeCloseWindow(StateReadInt("ScheduleHwnd"), ["brave.exe"])
    SafeCloseWindow(StateReadInt("CalendarHwnd"), ["brave.exe"])
    SafeCloseWindow(StateReadInt("GmailHwnd"), ["brave.exe"])

    outlook := StateReadInt("OutlookHwnd")
    if StateRead("OutlookOwned", "0") = "1"
        SafeCloseWindow(outlook, ["olk.exe", "OUTLOOK.EXE"])
    else
        RestoreOutlook(outlook
            , StateReadInt("OutlookPrevX"), StateReadInt("OutlookPrevY")
            , StateReadInt("OutlookPrevW"), StateReadInt("OutlookPrevH")
            , StateReadInt("OutlookPrevMinMax"))

    StateClear()
    TrayNote("Morning Dashboard closed.")
}

TrayNote(msg) {
    TrayTip msg, "Morning Dashboard"
}

LogError(msg) {
    try {
        DirCreate RepoRoot "\.state"
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", RepoRoot "\.state\dashboard.log"
    }
}
