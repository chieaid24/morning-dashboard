# Verifies that no private data can reach the public repository:
# nothing tracked under .private/ or .state/, no committed schedule image,
# no user-profile paths in tracked files, nothing private in git history,
# and no local config staged. Exits 1 on any failure.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$failures = @()

function Invoke-Git([string[]]$GitArgs) {
    $out = & git -C $RepoRoot @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

try {
    $tracked = @(Invoke-Git @('ls-files'))
    $staged = @(Invoke-Git @('diff', '--cached', '--name-only'))
    $historyPaths = @(Invoke-Git @('rev-list', '--objects', '--all')) |
        ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { $_ }
} catch {
    Write-Error "Privacy verification could not run git: $_"
    exit 1
}

# Pattern built so this tracked script never matches itself.
$privateNames = '(^|/)WEEKLY' + ' SCHEDULE\.jpg$'
$userProfile = 'C:' + '\\Users\\(?!you\b)'

if ($tracked -match '^\.private/') { $failures += '.private/ contains tracked files' }
if ($tracked -match '^\.state/') { $failures += '.state/ contains tracked files' }
if ($tracked -match $privateNames) { $failures += 'the schedule image is tracked' }
if ($tracked -match '(^|/)config\.local\.ini$') { $failures += 'config.local.ini is tracked' }

foreach ($file in $tracked) {
    $full = Join-Path $RepoRoot $file
    if (-not (Test-Path $full)) { continue }
    if (Select-String -Path $full -Pattern $userProfile -Quiet) {
        $failures += "tracked file contains a real user-profile path: $file"
    }
}

foreach ($pattern in @('^\.private/', '^\.state/', $privateNames, '(^|/)config\.local\.ini$')) {
    if ($historyPaths -match $pattern) {
        $failures += "git history contains a private path matching $pattern"
    }
}

foreach ($pattern in @('^\.private/', '^\.state/', $privateNames, '(^|/)config\.local\.ini$', '\.log$')) {
    if ($staged -match $pattern) {
        $failures += "a private or local file is staged, matching $pattern"
    }
}

foreach ($probe in @('.private/probe', '.state/probe', 'config.local.ini')) {
    & git -C $RepoRoot check-ignore -q -- $probe *> $null
    if ($LASTEXITCODE -ne 0) { $failures += "$probe is not gitignored" }
}

if ($failures) {
    Write-Host 'Privacy verification FAILED:' -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Privacy verification passed.'
exit 0
