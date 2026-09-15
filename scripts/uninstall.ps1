# Uninstalls the Morning Dashboard: tears down an active dashboard, stops
# the hotkey daemon, removes the Startup entry and runtime state. Keeps the
# private schedule image unless -RemovePrivateData is given. Never uninstalls
# Brave, Outlook, AutoHotkey, or PowerToys.

[CmdletBinding()]
param(
    [switch]$RemovePrivateData
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Step($msg) { Write-Host "==> $msg" }

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

$script = Join-Path $RepoRoot 'src\dashboard.ahk'
$stateFile = Join-Path $RepoRoot '.state\session.ini'

# Tear down an active dashboard first so its windows close gracefully.
$ahk = Find-AutoHotkey
if ($ahk -and (Test-Path $script) -and (Test-Path $stateFile)) {
    Step 'Closing active dashboard'
    Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '" close')
    $deadline = (Get-Date).AddSeconds(60)
    while ((Test-Path $stateFile) -and ((Get-Date) -lt $deadline)) { Start-Sleep -Milliseconds 500 }
}

Step 'Stopping hotkey daemon'
Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -like '*dashboard.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Step 'Removing Startup entry'
$lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Morning Dashboard.lnk'
if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force }

Step 'Removing runtime state'
$stateDir = Join-Path $RepoRoot '.state'
if (Test-Path $stateDir) { Remove-Item $stateDir -Recurse -Force }

if ($RemovePrivateData) {
    Step 'Removing private data'
    $privateDir = Join-Path $RepoRoot '.private'
    if (Test-Path $privateDir) { Remove-Item $privateDir -Recurse -Force }
} else {
    Step 'Keeping .private\ (use -RemovePrivateData to delete it)'
}

Write-Host 'Morning Dashboard uninstalled.'
