# Copies a new weekly schedule image into the gitignored .private\ folder
# and re-runs privacy verification. The image is never staged or committed.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Path)) { throw "Source image not found: $Path" }
if (-not (Test-Path (Join-Path $RepoRoot '.gitignore'))) { throw '.gitignore is missing; refusing to copy the private image.' }

& git -C $RepoRoot check-ignore -q -- '.private/probe' *> $null
if ($LASTEXITCODE -eq 1) { throw '.private/ is not gitignored; refusing to copy the private image.' }
if ($LASTEXITCODE -gt 1) {
    $gi = Get-Content (Join-Path $RepoRoot '.gitignore')
    if (-not ($gi -match '^\s*\.private/\s*$')) { throw '.private/ is not gitignored; refusing to copy the private image.' }
    Write-Warning 'git could not inspect this checkout; verified .private/ via .gitignore contents.'
}

$privateDir = Join-Path $RepoRoot '.private'
New-Item -ItemType Directory -Force -Path $privateDir | Out-Null
Copy-Item -Path $Path -Destination (Join-Path $privateDir 'WEEKLY SCHEDULE.jpg') -Force
Write-Host 'Schedule image updated in .private\'

& (Join-Path $PSScriptRoot 'verify-privacy.ps1')
exit $LASTEXITCODE
