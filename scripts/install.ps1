# Installs the Morning Dashboard: discovers dependencies (installing
# AutoHotkey v2 / PowerToys via winget when missing), writes the gitignored
# config.local.ini, copies the private schedule image, wires git hooks,
# registers the hotkey daemon in Startup, and starts it. Idempotent.

[CmdletBinding()]
param(
    # Absolute path to the private weekly schedule image. Copied (not moved)
    # into .private\, which is never committed.
    [string]$ScheduleImagePath
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Step($msg) { Write-Host "==> $msg" }
function Warn($msg) { Write-Warning $msg }

if ($env:OS -ne 'Windows_NT') { throw 'This installer must run on Windows.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required but was not found on PATH.' }

# Repo git commands can fail on UNC/foreign-owned checkouts (exit 128);
# callers fall back to reading .gitignore directly in that case.
function Invoke-RepoGit([string[]]$GitArgs) {
    & git -C $RepoRoot @GitArgs *> $null
    return $LASTEXITCODE
}

function Test-PrivateIgnored {
    $code = Invoke-RepoGit @('check-ignore', '-q', '--', '.private/probe')
    if ($code -eq 0) { return $true }
    if ($code -eq 1) { return $false }
    Warn 'git could not inspect this checkout; falling back to reading .gitignore.'
    $gi = Join-Path $RepoRoot '.gitignore'
    if (-not (Test-Path $gi)) { return $false }
    return [bool](Select-String -Path $gi -Pattern '^\s*\.private/\s*$' -Quiet)
}

function Install-WithWinget([string]$Id, [string[]]$ExtraArgs) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Warn "winget not available; cannot install $Id automatically."
        return
    }
    $common = @('--source', 'winget', '--silent', '--disable-interactivity',
                '--accept-package-agreements', '--accept-source-agreements')
    & winget install --id $Id --scope user @common @ExtraArgs
    if ($LASTEXITCODE -ne 0) {
        # Some manifests reject per-user scope; retry with the default scope.
        & winget install --id $Id @common @ExtraArgs
    }
}

function Find-AutoHotkey {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey32.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey32.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Find-Brave {
    $cmd = Get-Command brave.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($hive in 'HKLM:', 'HKCU:') {
        $key = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe"
        $path = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'(default)'
        if ($path -and (Test-Path $path)) { return $path }
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Find-PowerToys {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'),
        (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

# --- 1. AutoHotkey v2 -------------------------------------------------------
Step 'Checking AutoHotkey v2'
$ahk = Find-AutoHotkey
if (-not $ahk) {
    Step 'Installing AutoHotkey v2 with winget'
    Install-WithWinget 'AutoHotkey.AutoHotkey' @('--exact')
    $ahk = Find-AutoHotkey
}
if (-not $ahk) { throw 'AutoHotkey v2 was not found and could not be installed.' }
Step "AutoHotkey: $ahk"

# --- 2. PowerToys (optional) ------------------------------------------------
Step 'Checking PowerToys'
$powerToys = Find-PowerToys
if (-not $powerToys) {
    Step 'Installing PowerToys with winget'
    Install-WithWinget 'Microsoft.PowerToys' @()
    $powerToys = Find-PowerToys
}
if ($powerToys) { Step "PowerToys: $powerToys" }
else { Warn 'PowerToys unavailable; the dashboard works without it.' }

# --- 3. Brave ----------------------------------------------------------------
Step 'Checking Brave'
$brave = Find-Brave
if (-not $brave) { throw 'Brave was not found. Install Brave, then re-run this script.' }
Step "Brave: $brave"

# --- 4. Outlook --------------------------------------------------------------
Step 'Checking Outlook'
$classicOutlook = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' -ErrorAction SilentlyContinue).'(default)'
if ($classicOutlook -and -not (Test-Path $classicOutlook)) { $classicOutlook = $null }
$newOutlookAppId = $null
$pkg = Get-AppxPackage Microsoft.OutlookForWindows -ErrorAction SilentlyContinue
if ($pkg) { $newOutlookAppId = "$($pkg.PackageFamilyName)!Microsoft.OutlookforWindows" }
if (-not $classicOutlook -and -not $newOutlookAppId) {
    Warn 'No Outlook installation detected; the dashboard will try "outlook.exe" at launch.'
}
if ($classicOutlook) { Step "Classic Outlook: $classicOutlook" }
if ($newOutlookAppId) { Step "New Outlook: $newOutlookAppId" }

# --- 5. Local config ----------------------------------------------------------
$localConfig = Join-Path $RepoRoot 'config.local.ini'
$altLocalConfig = Join-Path $RepoRoot 'config\config.local.ini'
if ((Test-Path $localConfig) -or (Test-Path $altLocalConfig)) {
    Step 'config.local.ini already exists; leaving it untouched'
} else {
    Step 'Writing config.local.ini'
    # New Outlook is preferred when present; a classic install can exist
    # unconfigured and only show a profile/error dialog at launch.
    $prefer = if ($newOutlookAppId) { 'new' } else { 'classic' }
    @"
[General]
Hotkey=^!m
UsePowerToysWorkspace=false

[Brave]
Executable=$brave
ProfileDirectory=

[Outlook]
Prefer=$prefer
Executable=$classicOutlook
AppId=$newOutlookAppId

[Calendar]
Url=https://calendar.google.com/calendar/u/0/r/day

[Gmail]
Url1=https://mail.google.com/mail/u/1/#inbox
Url2=https://mail.google.com/mail/u/0/#inbox
Url3=https://mail.google.com/mail/u/2/#inbox

[Schedule]
LocalImage=.private\WEEKLY SCHEDULE.jpg
Viewer=viewer\schedule.html

[Monitors]
LeftMonitor=
RightMonitor=
"@ | Set-Content -Path $localConfig -Encoding ASCII
}

# --- 6. Private schedule image -------------------------------------------------
$privateDir = Join-Path $RepoRoot '.private'
$destImage = Join-Path $privateDir 'WEEKLY SCHEDULE.jpg'
if (-not (Test-Path (Join-Path $RepoRoot '.gitignore'))) { throw '.gitignore is missing; refusing to copy the private image.' }
if (-not (Test-PrivateIgnored)) { throw '.private/ is not gitignored; refusing to copy the private image.' }
if ($ScheduleImagePath) {
    if (-not (Test-Path $ScheduleImagePath)) { throw "Schedule image not found: $ScheduleImagePath" }
    New-Item -ItemType Directory -Force -Path $privateDir | Out-Null
    Copy-Item -Path $ScheduleImagePath -Destination $destImage -Force
    Step "Copied schedule image into .private\"
} elseif (Test-Path $destImage) {
    Step 'Schedule image already present in .private\'
} else {
    Warn 'No schedule image yet. Run: .\scripts\set-schedule-image.ps1 -Path "C:\path\to\schedule.jpg"'
}

# --- 7. Git hooks ---------------------------------------------------------------
Step 'Configuring repo-local git hooks'
$code = Invoke-RepoGit @('config', 'core.hooksPath', '.githooks')
if ($code -ne 0) { Warn 'Could not set core.hooksPath (git cannot use this checkout from Windows).' }

# --- 8. Startup entry -------------------------------------------------------------
Step 'Registering hotkey daemon in Startup'
$script = Join-Path $RepoRoot 'src\dashboard.ahk'

# A machine-local launcher retries until the repo is reachable, so logon
# autostart survives a WSL/network checkout that is still starting up.
$launcherDir = Join-Path $env:LOCALAPPDATA 'MorningDashboard'
New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
$launcher = Join-Path $launcherDir 'launcher.ahk'
@"
#Requires AutoHotkey v2.0
#NoTrayIcon
; Written by install.ps1. Waits for the repo to become reachable, then
; starts the Morning Dashboard tray daemon and exits.
scriptPath := "$script"
deadline := A_TickCount + 120000
while A_TickCount < deadline {
    if FileExist(scriptPath) {
        Run '"' A_AhkPath '" "' scriptPath '"'
        ExitApp
    }
    Sleep 3000
}
ExitApp
"@ | Set-Content -Path $launcher -Encoding ASCII

$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'Morning Dashboard.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = $ahk
$lnk.Arguments = '"' + $launcher + '"'
$lnk.Description = 'Morning Dashboard hotkey daemon'
$lnk.Save()
Step "Startup shortcut: $lnkPath"

# --- 9. (Re)start daemon ------------------------------------------------------------
Step 'Starting hotkey daemon'
Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -like '*dashboard.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '"')

# --- 10. Privacy verification ---------------------------------------------------------
Step 'Running privacy verification'
& (Join-Path $PSScriptRoot 'verify-privacy.ps1')
if ($LASTEXITCODE -ne 0) { Warn 'Privacy verification reported problems; fix them before pushing.' }

Write-Host ''
Write-Host 'Morning Dashboard installed. Press Ctrl+Alt+M to toggle it.'
