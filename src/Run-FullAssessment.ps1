<#
.SYNOPSIS
    Orchestrator script. Runs Mario Cuomo's Defender Adoption Helper
    plus (when available) the five Simplicity IT extension modules,
    and merges output into a single results.csv consumable by
    SimpleChannel's Sentinel readiness augmenter.

.DESCRIPTION
    This is the entry point most operators will use. Reads
    config/sentinelEnvironments.json, authenticates, invokes each
    module in sequence, and writes the combined CSV to
    output/results.csv. Opens output/dashboard.html on completion.

.PARAMETER EnvironmentsFile
    Path to the sentinelEnvironments.json config (subscription IDs,
    resource groups, workspace names).

.PARAMETER AuthMode
    User (interactive Connect-AzAccount) or App (service principal).

.PARAMETER ClientId
    App reg client id. Required when AuthMode = App.

.PARAMETER ClientSecret
    SecureString. Required when AuthMode = App.

.PARAMETER TenantId
    Entra tenant id. Required when AuthMode = App.

.PARAMETER SkipDashboard
    Do not open dashboard.html at the end. Useful in CI.

.EXAMPLE
    .\Run-FullAssessment.ps1 -EnvironmentsFile ..\config\sentinelEnvironments.json -AuthMode User

.NOTES
    Copyright Simplicity IT Inc., 2026. Licensed MIT.
    Based on Mario Cuomo's Defender Adoption Helper, copyright
    Microsoft Corporation, licensed MIT.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvironmentsFile,
    [ValidateSet("User", "App")][string]$AuthMode = "User",
    [string]$ClientId,
    [SecureString]$ClientSecret,
    [string]$TenantId,
    [switch]$SkipDashboard
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outputCsv = Join-Path $root "output\results.csv"
$dashboardHtml = Join-Path $root "output\dashboard.html"

if (-not (Test-Path $EnvironmentsFile)) {
    throw "Environments file not found: $EnvironmentsFile"
}

Write-Host "Simplicity IT Sentinel Migration Toolkit" -ForegroundColor Cyan
Write-Host "Orchestrator starting at $(Get-Date -Format o)" -ForegroundColor Cyan
Write-Host "Environments file: $EnvironmentsFile"
Write-Host "Auth mode: $AuthMode"
Write-Host ""

# --- Module 1: Mario's upstream Defender Adoption Helper ---
$mario = Join-Path $PSScriptRoot "DefenderAdoptionHelper.ps1"
if (Test-Path $mario) {
    Write-Host "[1/8] Running Defender Adoption Helper (upstream)..." -ForegroundColor Yellow
    $marioArgs = @{
        EnvironmentsFile = $EnvironmentsFile
        AuthMode         = $AuthMode
    }
    if ($AuthMode -eq "App") {
        $marioArgs["ClientId"] = $ClientId
        $marioArgs["ClientSecret"] = $ClientSecret
        $marioArgs["TenantId"] = $TenantId
    }
    & $mario @marioArgs
} else {
    Write-Warning "DefenderAdoptionHelper.ps1 not found; skipping upstream module."
}

# --- Modules 2-6: Simplicity IT extension modules ---
# All five modules went live 2026-06-13 with the v2 per-finding schema.
# Modules append directly to results.csv via the shared
# _AddResult-Standalone.ps1 helper.
$extensionModules = @(
    "SimplicityWorkbooksInventory.ps1",
    "SimplicityPlaybookInventory.ps1",
    "SimplicityHuntingQueryInventory.ps1",
    "SimplicityWatchlistInventory.ps1",
    "SimplicityConnectorMap.ps1"
)
$slot = 2
foreach ($mod in $extensionModules) {
    $path = Join-Path $PSScriptRoot $mod
    if (Test-Path $path) {
        Write-Host "[$slot/6] Running $mod..." -ForegroundColor Yellow
        & $path -EnvironmentsFile $EnvironmentsFile -AuthMode $AuthMode `
            -ClientId $ClientId -ClientSecret $ClientSecret -TenantId $TenantId `
            -OutputCsv $outputCsv -Append
    } else {
        Write-Warning "[$slot/6] $mod missing; skipping. Reclone the toolkit."
    }
    $slot++
}

Write-Host ""
Write-Host "Done at $(Get-Date -Format o)" -ForegroundColor Green
if (Test-Path $outputCsv) {
    $rowCount = (Get-Content $outputCsv | Measure-Object -Line).Lines - 1
    Write-Host "Results written to $outputCsv ($rowCount rows)" -ForegroundColor Green
}

if (-not $SkipDashboard -and (Test-Path $dashboardHtml)) {
    Write-Host "Opening dashboard..." -ForegroundColor Cyan
    Start-Process $dashboardHtml
}

Write-Host ""
Write-Host "Next: paste $outputCsv into SimpleChannel's Sentinel readiness augmenter at" -ForegroundColor Cyan
Write-Host "      https://channel.simpleintelligence.io/app/admin/sentinel-readiness" -ForegroundColor Cyan
Write-Host "      to generate four customer-facing deliverables in one Claude pass."  -ForegroundColor Cyan
